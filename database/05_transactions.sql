-- =============================================================
-- 05_transactions.sql - Testes de transacao (operacao critica)
--   psql -U postgres -d clinica_medica -f database/05_transactions.sql
--
-- Operacao critica: PAGAR UMA CONSULTA COM OS CREDITOS DA CARTEIRA
-- do paciente. Sao 2 escritas que precisam acontecer JUNTAS:
--   1) debitar o saldo da carteira
--   2) registrar o pagamento da consulta
-- Se so a 1a acontecer, o paciente perde dinheiro sem pagar;
-- se so a 2a, a clinica recebe sem debitar. Por isso: transacao.
-- =============================================================

-- Estado inicial das carteiras usadas nos testes
SELECT p.nome, c.saldo
FROM carteiras c JOIN pacientes p ON p.id = c.paciente_id
WHERE c.paciente_id IN (1, 2, 3)
ORDER BY c.paciente_id;
-- Ana = 1000.00 | Bruno = 500.00 | Carla = 100.00

-- =============================================================
-- CASO 1 - SUCESSO: Bruno paga a consulta 6 (350,00) -> COMMIT
-- =============================================================
BEGIN TRANSACTION;

UPDATE carteiras
SET saldo = saldo - 350.00, atualizado_em = CURRENT_TIMESTAMP
WHERE paciente_id = 2;

INSERT INTO pagamentos (consulta_id, valor, forma) VALUES (6, 350.00, 'CREDITO');

COMMIT;

SELECT saldo AS saldo_bruno_apos_commit FROM carteiras WHERE paciente_id = 2;   -- 150.00

-- =============================================================
-- CASO 2 - ROLLBACK MANUAL: alteracao feita e depois desfeita
-- =============================================================
BEGIN TRANSACTION;

UPDATE carteiras SET saldo = 0 WHERE paciente_id = 1;
SELECT saldo AS saldo_ana_dentro_da_transacao FROM carteiras WHERE paciente_id = 1;  -- 0.00

ROLLBACK;

SELECT saldo AS saldo_ana_apos_rollback FROM carteiras WHERE paciente_id = 1;        -- 1000.00

-- =============================================================
-- CASO 3 - FALHA: Carla (saldo 100,00) tenta pagar a consulta 7
-- (250,00). O debito deixaria o saldo em -150,00 e viola o
-- CHECK (saldo >= 0). A transacao e ABORTADA e nada e gravado.
-- (versao "crua", com o ERROR do psql: 05b_transacao_falha_demo.sql)
-- =============================================================

-- A operacao como funcao: valida o saldo e grava as 2 escritas.
CREATE OR REPLACE FUNCTION pagar_consulta_com_credito(p_consulta_id INT)
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_paciente INT;
    v_valor    NUMERIC(10,2);
    v_saldo    NUMERIC(10,2);
BEGIN
    SELECT paciente_id, valor INTO v_paciente, v_valor
    FROM consultas WHERE id = p_consulta_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Consulta % nao existe', p_consulta_id;
    END IF;

    -- FOR UPDATE trava a linha: dois pagamentos simultaneos nao
    -- conseguem usar o mesmo saldo duas vezes.
    SELECT saldo INTO v_saldo FROM carteiras
    WHERE paciente_id = v_paciente FOR UPDATE;

    IF v_saldo < v_valor THEN
        RAISE EXCEPTION 'Saldo insuficiente: disponivel %, necessario %', v_saldo, v_valor
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE carteiras SET saldo = saldo - v_valor, atualizado_em = CURRENT_TIMESTAMP
    WHERE paciente_id = v_paciente;

    INSERT INTO pagamentos (consulta_id, valor, forma)
    VALUES (p_consulta_id, v_valor, 'CREDITO');
END $$;

-- Tentativa: a excecao aborta tudo; o bloco captura so para exibir
-- a mensagem e conferir que os dados voltaram ao estado original.
DO $$
DECLARE
    saldo_antes NUMERIC(10,2);
    saldo_depois NUMERIC(10,2);
BEGIN
    SELECT saldo INTO saldo_antes FROM carteiras WHERE paciente_id = 3;

    BEGIN
        PERFORM pagar_consulta_com_credito(7);
        RAISE EXCEPTION 'FALHOU: pagamento sem saldo foi aceito';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE '[ROLLBACK] transacao abortada -> %', SQLERRM;
    END;

    SELECT saldo INTO saldo_depois FROM carteiras WHERE paciente_id = 3;
    IF saldo_depois <> saldo_antes
       OR EXISTS (SELECT 1 FROM pagamentos WHERE consulta_id = 7) THEN
        RAISE EXCEPTION 'FALHOU: dados ficaram alterados apos a falha';
    END IF;
    RAISE NOTICE '[OK] saldo da Carla continua % e a consulta 7 segue sem pagamento', saldo_depois;
END $$;

-- =============================================================
-- Conferencia final
-- =============================================================
SELECT p.nome, c.saldo,
       (SELECT string_agg(pg.consulta_id::text, ', ')
        FROM pagamentos pg JOIN consultas co ON co.id = pg.consulta_id
        WHERE co.paciente_id = p.id AND pg.forma = 'CREDITO') AS consultas_pagas_com_credito
FROM carteiras c JOIN pacientes p ON p.id = c.paciente_id
WHERE c.paciente_id IN (1, 2, 3)
ORDER BY c.paciente_id;
-- Ana = 1000.00 (rollback) | Bruno = 150.00 (commit, consulta 6) | Carla = 100.00 (falha)

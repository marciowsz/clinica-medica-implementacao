-- =============================================================
-- 03_indices.sql - Indices para otimizar consultas frequentes
--   psql -U postgres -d clinica_medica -f database/03_indices.sql
--
-- Com so 6 pacientes o PostgreSQL sempre prefere ler a tabela
-- inteira (Seq Scan), porque e mais barato. Para o EXPLAIN mostrar
-- a diferenca real, primeiro e gerada uma CARGA SINTETICA de
-- 20.000 pacientes e 60.000 consultas.
-- =============================================================

DROP INDEX IF EXISTS idx_pacientes_email_lower;
DROP INDEX IF EXISTS idx_consultas_status_data;

-- -------------------------------------------------------------
-- Carga sintetica (volume parecido com o de uma clinica real)
-- -------------------------------------------------------------
INSERT INTO pacientes (nome, cpf, data_nascimento, email)
SELECT 'Paciente ' || i,
       lpad((10000000000 + i)::text, 11, '0'),
       DATE '1950-01-01' + (i % 25000),
       'Paciente' || i || '@Email.com'
FROM generate_series(1, 20000) AS i;

INSERT INTO consultas (paciente_id, medico_id, data_hora, status, valor)
SELECT 7 + (i % 20000),                                   -- pacientes sinteticos
       1 + (i % 5),                                       -- 5 medicos
       TIMESTAMP '2020-01-01 07:00' + i * INTERVAL '30 minutes',
       (ARRAY['REALIZADA', 'REALIZADA', 'AGENDADA', 'CANCELADA'])[1 + (i % 4)],
       180 + (i % 5) * 40
FROM generate_series(1, 60000) AS i;

ANALYZE pacientes;
ANALYZE consultas;

-- =============================================================
-- INDICE 1 (SIMPLES) - busca de paciente por e-mail
-- Consulta frequente: login no portal / recepcao procurando o
-- cadastro. A busca ignora maiusculas, entao usa lower(email).
-- (O UNIQUE de email nao ajuda aqui: ele indexa o texto original,
--  nao lower(email).)
-- =============================================================

-- ANTES: sem indice -> Seq Scan (le as 20.006 linhas)
EXPLAIN ANALYZE
SELECT id, nome, cpf FROM pacientes WHERE lower(email) = 'paciente12345@email.com';

CREATE INDEX idx_pacientes_email_lower ON pacientes (lower(email));
ANALYZE pacientes;

-- DEPOIS: Index Scan usando idx_pacientes_email_lower
EXPLAIN ANALYZE
SELECT id, nome, cpf FROM pacientes WHERE lower(email) = 'paciente12345@email.com';

-- =============================================================
-- INDICE 2 (COMPOSTO) - relatorio de consultas por status e periodo
-- Consulta frequente: relatorio mensal de CANCELAMENTOS (taxa de
-- faltas e receita perdida). Coluna de igualdade (status) primeiro
-- e a de intervalo (data_hora) depois: o indice vai direto ao trecho.
--
-- Por que CANCELADA? O indice unico parcial uq_consulta_medico_horario
-- (WHERE status <> 'CANCELADA') ja atende relatorios de consultas
-- nao canceladas. Para as canceladas nao existe indice nenhum.
-- =============================================================

-- ANTES: sem indice -> Seq Scan nas 60.008 consultas
EXPLAIN ANALYZE
SELECT COUNT(*) AS canceladas, SUM(valor) AS receita_perdida
FROM consultas
WHERE status = 'CANCELADA'
  AND data_hora >= '2021-03-01' AND data_hora < '2021-04-01';

CREATE INDEX idx_consultas_status_data ON consultas (status, data_hora);
ANALYZE consultas;

-- DEPOIS: Index/Bitmap Scan usando idx_consultas_status_data
EXPLAIN ANALYZE
SELECT COUNT(*) AS canceladas, SUM(valor) AS receita_perdida
FROM consultas
WHERE status = 'CANCELADA'
  AND data_hora >= '2021-03-01' AND data_hora < '2021-04-01';

-- =============================================================
-- Verificacao automatica: os planos DEPOIS usam os indices
-- =============================================================
DO $$
DECLARE
    linha RECORD;
    plano TEXT;
BEGIN
    plano := '';
    FOR linha IN EXECUTE
        'EXPLAIN SELECT id FROM pacientes WHERE lower(email) = ''paciente12345@email.com'''
    LOOP plano := plano || linha."QUERY PLAN" || ' '; END LOOP;
    IF plano NOT LIKE '%idx_pacientes_email_lower%' THEN
        RAISE EXCEPTION 'FALHOU: indice de e-mail nao usado. Plano: %', plano;
    END IF;
    RAISE NOTICE 'OK: busca por e-mail usa idx_pacientes_email_lower';

    plano := '';
    FOR linha IN EXECUTE
        'EXPLAIN SELECT COUNT(*) FROM consultas WHERE status = ''CANCELADA''
           AND data_hora >= ''2021-03-01'' AND data_hora < ''2021-04-01'''
    LOOP plano := plano || linha."QUERY PLAN" || ' '; END LOOP;
    IF plano NOT LIKE '%idx_consultas_status_data%' THEN
        RAISE EXCEPTION 'FALHOU: indice composto nao usado. Plano: %', plano;
    END IF;
    RAISE NOTICE 'OK: relatorio de cancelamentos usa idx_consultas_status_data';
END $$;

-- Tamanho ocupado por cada indice (indices tambem gastam espaco)
SELECT indexrelname AS indice, pg_size_pretty(pg_relation_size(indexrelid)) AS tamanho
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_pacientes_email_lower', 'idx_consultas_status_data');

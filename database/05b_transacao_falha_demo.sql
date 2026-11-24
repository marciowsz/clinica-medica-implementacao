-- =============================================================
-- 05b_transacao_falha_demo.sql - Teste de falha "cru" (sem captura)
--   psql -U postgres -d clinica_medica -f database/05b_transacao_falha_demo.sql
--
-- Rodar DEPOIS do 05_transactions.sql. Os ERRORs abaixo sao
-- ESPERADOS: mostram o PostgreSQL abortando a transacao.
-- =============================================================

-- Saldo da Carla ANTES: 100.00
SELECT saldo AS saldo_carla_antes FROM carteiras WHERE paciente_id = 3;

BEGIN TRANSACTION;

-- 1) Debito de 250,00 com saldo de 100,00 -> viola CHECK (saldo >= 0)
UPDATE carteiras SET saldo = saldo - 250.00 WHERE paciente_id = 3;
-- ERROR:  new row for relation "carteiras" violates check constraint "carteiras_saldo_check"

-- 2) Ignorado: a transacao ja esta abortada
INSERT INTO pagamentos (consulta_id, valor, forma) VALUES (7, 250.00, 'CREDITO');
-- ERROR:  current transaction is aborted, commands ignored until end of transaction block

-- 3) Como houve erro, o COMMIT vira ROLLBACK automaticamente
COMMIT;
-- ROLLBACK

-- Saldo da Carla DEPOIS: continua 100.00 e a consulta 7 nao foi paga
SELECT saldo AS saldo_carla_depois FROM carteiras WHERE paciente_id = 3;
SELECT COUNT(*) AS pagamentos_da_consulta_7 FROM pagamentos WHERE consulta_id = 7;

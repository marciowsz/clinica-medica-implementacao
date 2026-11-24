-- =============================================================
-- 04_security.sql - Usuarios, papeis e permissoes
--   psql -U postgres -d clinica_medica -f database/04_security.sql
--
-- Principio do menor privilegio: cada usuario recebe so o que
-- precisa. As permissoes sao dadas a PAPEIS (grupos) e os usuarios
-- herdam do papel; trocar alguem de funcao = trocar o papel.
--
-- ATENCAO: as senhas abaixo sao de DESENVOLVIMENTO. Em producao,
-- troque com ALTER ROLE ... PASSWORD e nunca as versione no Git.
-- =============================================================

-- Remove usuarios/papeis de execucoes anteriores (script pode rodar de novo)
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['admin_clinica', 'analista', 'app_user',
                             'papel_admin', 'papel_analista', 'papel_app']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('DROP OWNED BY %I', r);
            EXECUTE format('DROP ROLE %I', r);
        END IF;
    END LOOP;
END $$;

-- Ninguem acessa nada "por padrao": tudo sera concedido explicitamente
REVOKE ALL ON SCHEMA public FROM PUBLIC;
DO $$ BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
END $$;

-- -------------------------------------------------------------
-- PAPEIS (grupos, sem login)
-- -------------------------------------------------------------
CREATE ROLE papel_admin    NOLOGIN;   -- leitura, escrita e exclusao
CREATE ROLE papel_analista NOLOGIN;   -- somente leitura (relatorios)
CREATE ROLE papel_app      NOLOGIN;   -- aplicacao: le e grava, NAO exclui

DO $$ BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO papel_admin, papel_analista, papel_app',
                   current_database());
END $$;
GRANT USAGE ON SCHEMA public TO papel_admin, papel_analista, papel_app;

-- Admin: SELECT, INSERT, UPDATE e DELETE em todas as tabelas
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO papel_admin;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO papel_admin;

-- Analista: apenas SELECT
GRANT SELECT ON ALL TABLES IN SCHEMA public TO papel_analista;

-- Aplicacao (app_user): le e grava, mas nao apaga nada
-- e nao altera o prontuario depois de criado (registro medico).
GRANT SELECT, INSERT, UPDATE ON ALL TABLES    IN SCHEMA public TO papel_app;
GRANT USAGE, SELECT          ON ALL SEQUENCES IN SCHEMA public TO papel_app;
REVOKE UPDATE ON prontuarios FROM papel_app;

-- -------------------------------------------------------------
-- USUARIOS (com login) herdando dos papeis
-- -------------------------------------------------------------
CREATE ROLE admin_clinica LOGIN PASSWORD 'Admin#Dev2026'    IN ROLE papel_admin;
CREATE ROLE analista      LOGIN PASSWORD 'Analista#Dev2026' IN ROLE papel_analista;
CREATE ROLE app_user      LOGIN PASSWORD 'App#Dev2026'      IN ROLE papel_app
                          CONNECTION LIMIT 20;

-- Resumo das permissoes por papel
SELECT grantee AS papel, table_name AS tabela,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS permissoes
FROM information_schema.role_table_grants
WHERE grantee IN ('papel_admin', 'papel_analista', 'papel_app')
  AND table_name IN ('pacientes', 'prontuarios')
GROUP BY grantee, table_name
ORDER BY grantee, table_name;

-- =============================================================
-- DEMONSTRACAO: o ANALISTA tenta apagar um paciente
-- =============================================================
SET ROLE analista;

-- Leitura funciona
SELECT current_user AS usuario, COUNT(*) AS pacientes_visiveis FROM pacientes;

-- Exclusao e NEGADA: "permissao negada para tabela pacientes"
DO $$
BEGIN
    DELETE FROM pacientes WHERE id = 1;
    RAISE EXCEPTION 'FALHOU: o analista conseguiu apagar um paciente';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '[analista] DELETE negado -> %', SQLERRM;
END $$;

-- Escrita tambem e NEGADA
DO $$
BEGIN
    UPDATE carteiras SET saldo = 999999 WHERE paciente_id = 1;
    RAISE EXCEPTION 'FALHOU: o analista conseguiu alterar um saldo';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '[analista] UPDATE negado -> %', SQLERRM;
END $$;

RESET ROLE;

-- =============================================================
-- DEMONSTRACAO: a APLICACAO (app_user) nao pode apagar dados
-- =============================================================
SET ROLE app_user;
DO $$
BEGIN
    DELETE FROM consultas WHERE id = 8;
    RAISE EXCEPTION 'FALHOU: app_user conseguiu apagar uma consulta';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE '[app_user] DELETE negado -> %', SQLERRM;
END $$;
RESET ROLE;

-- =============================================================
-- DEMONSTRACAO: o ADMIN pode apagar (feito em transacao e
-- desfeito com ROLLBACK, para nao perder o dado de teste)
-- =============================================================
SET ROLE admin_clinica;
BEGIN;
DELETE FROM paciente_telefones WHERE paciente_id = 4 AND tipo = 'TRABALHO';
DO $$ BEGIN
    RAISE NOTICE '[admin_clinica] DELETE permitido (sera desfeito com ROLLBACK)';
END $$;
ROLLBACK;
RESET ROLE;

-- Para ver o erro "cru", conecte como o analista em outro terminal:
--   psql -U analista -d clinica_medica -c "DELETE FROM pacientes WHERE id = 1"
--   ERROR:  permission denied for table pacientes

-- =============================================================
-- 01_ddl.sql - Criacao do banco e das tabelas (DDL)
-- Modelo logico da Semana 15 (3FN) implementado no PostgreSQL 16+
--
-- Executar como superusuario, SO na criacao do banco:
--   psql -U postgres -f database/01_ddl.sql
-- =============================================================

-- Cria o banco somente se ainda nao existir (\gexec executa o texto gerado)
SELECT 'CREATE DATABASE clinica_medica ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'clinica_medica')\gexec

\c clinica_medica

DROP TABLE IF EXISTS carteiras, pagamentos, prescricoes, medicamentos, prontuarios,
                     consultas, medicos, especialidades,
                     paciente_telefones, pacientes CASCADE;

-- -------------------------------------------------------------
-- ESPECIALIDADES
-- -------------------------------------------------------------
CREATE TABLE especialidades (
    id         SERIAL       PRIMARY KEY,
    nome       VARCHAR(60)  NOT NULL UNIQUE,
    descricao  VARCHAR(200) NOT NULL
);

-- -------------------------------------------------------------
-- PACIENTES
-- -------------------------------------------------------------
CREATE TABLE pacientes (
    id               SERIAL       PRIMARY KEY,
    nome             VARCHAR(120) NOT NULL,
    cpf              CHAR(11)     NOT NULL UNIQUE CHECK (cpf ~ '^[0-9]{11}$'),
    data_nascimento  DATE         NOT NULL CHECK (data_nascimento > DATE '1900-01-01'),
    email            VARCHAR(120) NOT NULL UNIQUE CHECK (email LIKE '%_@_%._%'),
    criado_em        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------
-- PACIENTE_TELEFONES (1FN: atributo multivalorado)
-- -------------------------------------------------------------
CREATE TABLE paciente_telefones (
    paciente_id  INT         NOT NULL REFERENCES pacientes(id) ON DELETE CASCADE,
    telefone     VARCHAR(11) NOT NULL CHECK (telefone ~ '^[0-9]{10,11}$'),
    tipo         VARCHAR(12) NOT NULL DEFAULT 'CELULAR'
                 CHECK (tipo IN ('CELULAR', 'RESIDENCIAL', 'TRABALHO')),
    PRIMARY KEY (paciente_id, telefone)
);

-- -------------------------------------------------------------
-- MEDICOS
-- -------------------------------------------------------------
CREATE TABLE medicos (
    id                SERIAL        PRIMARY KEY,
    nome              VARCHAR(120)  NOT NULL,
    crm               VARCHAR(15)   NOT NULL UNIQUE,
    especialidade_id  INT           NOT NULL REFERENCES especialidades(id),
    valor_consulta    NUMERIC(10,2) NOT NULL CHECK (valor_consulta > 0)
);

-- -------------------------------------------------------------
-- CONSULTAS
-- -------------------------------------------------------------
CREATE TABLE consultas (
    id           SERIAL        PRIMARY KEY,
    paciente_id  INT           NOT NULL REFERENCES pacientes(id),
    medico_id    INT           NOT NULL REFERENCES medicos(id),
    data_hora    TIMESTAMP     NOT NULL,
    status       VARCHAR(12)   NOT NULL DEFAULT 'AGENDADA'
                 CHECK (status IN ('AGENDADA', 'REALIZADA', 'CANCELADA')),
    valor        NUMERIC(10,2) NOT NULL CHECK (valor >= 0)
);

-- Regra de negocio: um medico nao atende dois pacientes no mesmo horario
CREATE UNIQUE INDEX uq_consulta_medico_horario
    ON consultas (medico_id, data_hora) WHERE status <> 'CANCELADA';

-- -------------------------------------------------------------
-- PRONTUARIOS (1:1 com consultas -> PK = FK)
-- -------------------------------------------------------------
CREATE TABLE prontuarios (
    consulta_id  INT       PRIMARY KEY REFERENCES consultas(id),
    diagnostico  TEXT      NOT NULL,
    observacoes  TEXT,
    criado_em    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------
-- MEDICAMENTOS
-- -------------------------------------------------------------
CREATE TABLE medicamentos (
    id               SERIAL      PRIMARY KEY,
    nome             VARCHAR(80) NOT NULL,
    principio_ativo  VARCHAR(80) NOT NULL,
    apresentacao     VARCHAR(40) NOT NULL,
    UNIQUE (nome, apresentacao)
);

-- -------------------------------------------------------------
-- PRESCRICOES (associativa N:N consultas x medicamentos)
-- -------------------------------------------------------------
CREATE TABLE prescricoes (
    consulta_id     INT          NOT NULL REFERENCES consultas(id),
    medicamento_id  INT          NOT NULL REFERENCES medicamentos(id),
    posologia       VARCHAR(120) NOT NULL,
    duracao_dias    INT          NOT NULL CHECK (duracao_dias > 0),
    PRIMARY KEY (consulta_id, medicamento_id)
);

-- -------------------------------------------------------------
-- PAGAMENTOS (1:1 com consultas)
-- -------------------------------------------------------------
CREATE TABLE pagamentos (
    id           SERIAL        PRIMARY KEY,
    consulta_id  INT           NOT NULL UNIQUE REFERENCES consultas(id),
    valor        NUMERIC(10,2) NOT NULL CHECK (valor > 0),
    forma        VARCHAR(10)   NOT NULL
                 CHECK (forma IN ('PIX', 'CARTAO', 'DINHEIRO', 'CONVENIO', 'CREDITO')),
    pago_em      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------
-- CARTEIRAS (novo nesta semana)
-- Creditos pre-pagos do paciente, usados para pagar consultas.
-- E a tabela da operacao critica testada em 05_transactions.sql.
-- O CHECK impede saldo negativo: e ele que faz a transacao falhar.
-- -------------------------------------------------------------
CREATE TABLE carteiras (
    paciente_id    INT           PRIMARY KEY REFERENCES pacientes(id),
    saldo          NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (saldo >= 0),
    atualizado_em  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

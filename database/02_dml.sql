-- =============================================================
-- 02_dml.sql - Dados de teste (DML)
-- Minimo de 5 registros por tabela principal.
--   psql -U postgres -d clinica_medica -f database/02_dml.sql
-- =============================================================

BEGIN;

INSERT INTO especialidades (id, nome, descricao) VALUES
    (1, 'Cardiologia',   'Doencas do coracao e do sistema circulatorio'),
    (2, 'Pediatria',     'Saude de criancas e adolescentes'),
    (3, 'Ortopedia',     'Ossos, articulacoes, musculos e ligamentos'),
    (4, 'Dermatologia',  'Pele, cabelos e unhas'),
    (5, 'Clinica Geral', 'Atendimento primario e encaminhamentos');

INSERT INTO pacientes (id, nome, cpf, data_nascimento, email) VALUES
    (1, 'Ana Souza',      '12345678901', '1990-04-12', 'ana.souza@email.com'),
    (2, 'Bruno Almeida',  '23456789012', '1985-09-30', 'bruno.almeida@email.com'),
    (3, 'Carla Mendes',   '34567890123', '2015-01-05', 'carla.mendes@email.com'),
    (4, 'Diego Ferreira', '45678901234', '1978-11-22', 'diego.ferreira@email.com'),
    (5, 'Elisa Rocha',    '56789012345', '2001-06-17', 'elisa.rocha@email.com'),
    (6, 'Fabio Costa',    '67890123456', '1995-02-08', 'fabio.costa@email.com');

INSERT INTO paciente_telefones (paciente_id, telefone, tipo) VALUES
    (1, '98999990001', 'CELULAR'),
    (1, '9832220001',  'RESIDENCIAL'),
    (2, '98999990002', 'CELULAR'),
    (3, '98999990003', 'CELULAR'),
    (4, '98999990004', 'CELULAR'),
    (4, '9832440004',  'TRABALHO'),
    (5, '98999990005', 'CELULAR'),
    (6, '98999990006', 'CELULAR');

INSERT INTO medicos (id, nome, crm, especialidade_id, valor_consulta) VALUES
    (1, 'Dr. Paulo Lima',       '10234-MA', 1, 350.00),
    (2, 'Dra. Fernanda Rocha',  '20456-MA', 2, 250.00),
    (3, 'Dr. Ricardo Nunes',    '30678-MA', 3, 300.00),
    (4, 'Dra. Juliana Martins', '40890-MA', 4, 280.00),
    (5, 'Dr. Marcos Pereira',   '50112-MA', 5, 180.00);

INSERT INTO consultas (id, paciente_id, medico_id, data_hora, status, valor) VALUES
    (1, 1, 1, '2026-12-01 09:00', 'REALIZADA', 350.00),
    (2, 3, 2, '2026-12-01 10:00', 'REALIZADA', 250.00),
    (3, 4, 3, '2026-12-02 14:00', 'REALIZADA', 300.00),
    (4, 5, 4, '2026-12-02 15:30', 'REALIZADA', 280.00),
    (5, 6, 5, '2026-12-03 08:00', 'REALIZADA', 180.00),
    (6, 2, 1, '2026-12-10 09:30', 'AGENDADA',  350.00),
    (7, 3, 2, '2026-12-11 10:00', 'AGENDADA',  250.00),
    (8, 1, 5, '2026-12-12 11:00', 'CANCELADA', 180.00);

INSERT INTO prontuarios (consulta_id, diagnostico, observacoes) VALUES
    (1, 'Hipertensao arterial leve',  'Retorno em 30 dias'),
    (2, 'Amigdalite bacteriana',      'Repouso e hidratacao'),
    (3, 'Entorse de tornozelo grau I','Gelo e imobilizacao por 7 dias'),
    (4, 'Dermatite de contato',       'Evitar o produto que causou a reacao'),
    (5, 'Check-up anual sem alteracoes', 'Exames de rotina solicitados');

INSERT INTO medicamentos (id, nome, principio_ativo, apresentacao) VALUES
    (1, 'Losartana',     'Losartana potassica',     '50 mg comprimido'),
    (2, 'Amoxicilina',   'Amoxicilina',             '250 mg/5 ml suspensao'),
    (3, 'Dipirona',      'Dipirona monoidratada',   '500 mg/ml gotas'),
    (4, 'Ibuprofeno',    'Ibuprofeno',              '600 mg comprimido'),
    (5, 'Dexametasona',  'Dexametasona',            '1 mg/g creme'),
    (6, 'Loratadina',    'Loratadina',              '10 mg comprimido');

INSERT INTO prescricoes (consulta_id, medicamento_id, posologia, duracao_dias) VALUES
    (1, 1, '1 comprimido pela manha',          30),
    (2, 2, '5 ml a cada 8 horas',              10),
    (2, 3, '15 gotas se febre, ate 4x ao dia',  5),
    (3, 4, '1 comprimido a cada 8 horas',       5),
    (4, 5, 'Aplicar 2x ao dia na regiao',       7),
    (4, 6, '1 comprimido ao dia',               10);

INSERT INTO pagamentos (consulta_id, valor, forma) VALUES
    (1, 350.00, 'PIX'),
    (2, 250.00, 'CARTAO'),
    (3, 300.00, 'CONVENIO'),
    (4, 280.00, 'PIX'),
    (5, 180.00, 'DINHEIRO');

INSERT INTO carteiras (paciente_id, saldo) VALUES
    (1, 1000.00),
    (2,  500.00),
    (3,  100.00),
    (4,    0.00),
    (5,  250.00),
    (6,   80.00);

COMMIT;

-- Ajusta as sequences depois dos INSERTs com id explicito
SELECT setval('especialidades_id_seq', (SELECT MAX(id) FROM especialidades));
SELECT setval('pacientes_id_seq',      (SELECT MAX(id) FROM pacientes));
SELECT setval('medicos_id_seq',        (SELECT MAX(id) FROM medicos));
SELECT setval('consultas_id_seq',      (SELECT MAX(id) FROM consultas));
SELECT setval('medicamentos_id_seq',   (SELECT MAX(id) FROM medicamentos));

-- Conferencia: quantidade de registros por tabela
SELECT 'especialidades' AS tabela, COUNT(*) AS registros FROM especialidades
UNION ALL SELECT 'pacientes',          COUNT(*) FROM pacientes
UNION ALL SELECT 'paciente_telefones', COUNT(*) FROM paciente_telefones
UNION ALL SELECT 'medicos',            COUNT(*) FROM medicos
UNION ALL SELECT 'consultas',          COUNT(*) FROM consultas
UNION ALL SELECT 'prontuarios',        COUNT(*) FROM prontuarios
UNION ALL SELECT 'medicamentos',       COUNT(*) FROM medicamentos
UNION ALL SELECT 'prescricoes',        COUNT(*) FROM prescricoes
UNION ALL SELECT 'pagamentos',         COUNT(*) FROM pagamentos
UNION ALL SELECT 'carteiras',          COUNT(*) FROM carteiras;

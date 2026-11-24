# Clínica Médica: Implementação Física, Índices, Segurança e Transações

Entregável da Semana 16 da disciplina **Modelagem de Banco de Dados**. Implementa no **PostgreSQL** o modelo lógico da Semana 15 ([clinica-medica-modelagem](https://github.com/marciowsz/clinica-medica-modelagem)).

**Autor:** Marcio Rogério Reis Freire Junior ([@marciowsz](https://github.com/marciowsz))

```
clinica-medica-implementacao/
├── database/
│   ├── 01_ddl.sql                    # cria o banco e as 10 tabelas (PK, FK, NOT NULL, UNIQUE, CHECK)
│   ├── 02_dml.sql                    # dados de teste (5+ registros por tabela principal)
│   ├── 03_indices.sql                # 2 índices + EXPLAIN ANALYZE antes e depois
│   ├── 04_security.sql               # papéis, usuários (admin, analista, app) e permissões
│   ├── 05_transactions.sql           # operação crítica: COMMIT, ROLLBACK e falha por saldo
│   └── 05b_transacao_falha_demo.sql  # a mesma falha "crua", mostrando o ERROR do psql
└── .github/workflows/
    └── validar-banco.yml             # roda tudo em um PostgreSQL 16 a cada push
```

### Como executar (em ordem)

```bash
psql -U postgres -f database/01_ddl.sql                    # cria o banco clinica_medica
psql -U postgres -d clinica_medica -f database/02_dml.sql
psql -U postgres -d clinica_medica -f database/03_indices.sql
psql -U postgres -d clinica_medica -f database/04_security.sql
psql -U postgres -d clinica_medica -f database/05_transactions.sql
psql -U postgres -d clinica_medica -f database/05b_transacao_falha_demo.sql   # ERRORs esperados
```

Com Docker:

```bash
docker run -d --name clinica -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:16
docker exec -i clinica psql -U postgres < database/01_ddl.sql
for f in database/0[2-5]*.sql; do docker exec -i clinica psql -U postgres -d clinica_medica < "$f"; done
```

> O `01_ddl.sql` usa `\gexec` e `\c` (comandos do `psql`) para criar o banco e se conectar a ele.

---

## Parte 1: Manipulação e validação de dados

### DDL: [`01_ddl.sql`](database/01_ddl.sql)

Cria o banco `clinica_medica` e as tabelas do modelo lógico (3FN), com todas as constraints pedidas:

| Constraint | Exemplos |
|---|---|
| `PRIMARY KEY` | `pacientes.id`; PK composta em `prescricoes (consulta_id, medicamento_id)` e `paciente_telefones (paciente_id, telefone)`; PK = FK em `prontuarios.consulta_id` e `carteiras.paciente_id` |
| `FOREIGN KEY` | `consultas.paciente_id → pacientes`, `consultas.medico_id → medicos`, `medicos.especialidade_id → especialidades`, `pagamentos.consulta_id → consultas`... |
| `NOT NULL` | todos os campos obrigatórios (nome, CPF, e-mail, data_hora, valor...) |
| `UNIQUE` | `pacientes.cpf`, `pacientes.email`, `medicos.crm`, `especialidades.nome`, `pagamentos.consulta_id`, `(medicamentos.nome, apresentacao)` |
| `CHECK` | CPF com 11 dígitos, formato do e-mail, `valor_consulta > 0`, status permitido, `saldo >= 0` |

**Novidade desta semana:** a tabela `carteiras` (créditos pré-pagos do paciente), usada na operação crítica da Parte 3.

### DML: [`02_dml.sql`](database/02_dml.sql)

Simula o cenário real da clínica:

| Tabela | Registros |
|---|---|
| especialidades | 5 |
| pacientes | 6 |
| paciente_telefones | 8 |
| medicos | 5 |
| consultas | 8 (realizadas, agendadas e uma cancelada) |
| prontuarios | 5 |
| medicamentos | 6 |
| prescricoes | 6 |
| pagamentos | 5 |
| carteiras | 6 |

---

## Parte 2: Otimização e segurança

### Índices: [`03_indices.sql`](database/03_indices.sql)

Com apenas 6 pacientes, o PostgreSQL sempre lê a tabela inteira, porque é mais barato que usar um índice. Para o `EXPLAIN ANALYZE` mostrar a diferença real, o script gera antes uma **carga sintética de 20.000 pacientes e 60.000 consultas**, que é o volume de uma clínica real em poucos anos.

| Índice | Tipo | Consulta otimizada | Antes | Depois |
|---|---|---|---|---|
| `idx_pacientes_email_lower` em `pacientes (lower(email))` | **simples** (de expressão) | Buscar o paciente pelo e-mail no login ou na recepção, sem diferenciar maiúsculas | `Seq Scan`: leu 20.006 linhas, **3,69 ms** | `Index Scan`: leu 1 linha, **0,04 ms** (cerca de 90× mais rápido) |
| `idx_consultas_status_data` em `consultas (status, data_hora)` | **composto** | Relatório mensal de consultas **canceladas** (taxa de faltas e receita perdida) | `Seq Scan`: leu 60.008 linhas, **2,82 ms** | `Bitmap Index Scan`: foi direto às 372 linhas, **0,14 ms** (cerca de 20× mais rápido) |

Trecho real do `EXPLAIN ANALYZE` antes e depois do índice de e-mail:

```
-- ANTES
Seq Scan on pacientes  (cost=0.00..547.09 rows=100) (actual time=2.213..3.680 rows=1)
  Filter: (lower((email)::text) = 'paciente12345@email.com'::text)
  Rows Removed by Filter: 20005
Execution Time: 3.692 ms

-- DEPOIS
Index Scan using idx_pacientes_email_lower on pacientes  (cost=0.29..8.30 rows=1) (actual time=0.028..0.029 rows=1)
  Index Cond: (lower((email)::text) = 'paciente12345@email.com'::text)
Execution Time: 0.039 ms
```

**Decisões de projeto:**
- **Por que `lower(email)`?** O `UNIQUE` de `email` já cria um índice, mas sobre o texto original. A busca ignora maiúsculas (`Ana@Email.com` = `ana@email.com`), então o índice precisa ser sobre `lower(email)`. Se não for, o PostgreSQL não consegue usá-lo.
- **Por que `status` antes de `data_hora`?** Em um índice composto, a coluna comparada por **igualdade** vem primeiro e a de **intervalo** depois. Assim o índice vai direto ao trecho `CANCELADA` e, dentro dele, ao intervalo de datas.
- **Por que o relatório de canceladas?** Ao testar com `status = 'REALIZADA'`, o `EXPLAIN` mostrou que o PostgreSQL já usava o índice único parcial `uq_consulta_medico_horario` (`WHERE status <> 'CANCELADA'`), criado para impedir dois pacientes no mesmo horário. Um índice novo para esse caso seria **redundante** (veja a Parte 4). As consultas canceladas não tinham nenhum índice, por isso o índice composto foi direcionado a elas.
- O script termina **verificando automaticamente** que os dois planos usam os índices e mostrando quanto espaço cada um ocupa (808 kB e 2,4 MB).

### Usuários e permissões: [`04_security.sql`](database/04_security.sql)

As permissões são dadas a **papéis (grupos)** e os usuários herdam do papel. Trocar alguém de função é só trocar o papel.

| Usuário | Papel | SELECT | INSERT | UPDATE | DELETE | Uso |
|---|---|:-:|:-:|:-:|:-:|---|
| `admin_clinica` | `papel_admin` | ✅ | ✅ | ✅ | ✅ | DBA / administrador do sistema |
| `analista` | `papel_analista` | ✅ | ❌ | ❌ | ❌ | Relatórios e BI (somente leitura) |
| `app_user` | `papel_app` | ✅ | ✅ | ✅* | ❌ | Usuário com que a **aplicação** se conecta (nunca o `postgres`) |

\* O `app_user` não pode alterar o prontuário depois de criado, porque é registro médico. Ele também tem limite de 20 conexões.

Além disso, o script faz `REVOKE ALL ... FROM PUBLIC`, para que **ninguém** tenha acesso por padrão.

**Demonstração: o analista tenta apagar um paciente**

Saída do script (o bloco captura o erro para seguir em frente):

```
NOTICE: [analista] DELETE negado -> permissão negada para tabela pacientes
NOTICE: [analista] UPDATE negado -> permissão negada para tabela carteiras
NOTICE: [app_user] DELETE negado -> permissão negada para tabela consultas
NOTICE: [admin_clinica] DELETE permitido (sera desfeito com ROLLBACK)
```

Conectando de verdade como o analista:

```
$ psql -U analista -d clinica_medica -c "SELECT COUNT(*) FROM pacientes"
 count
-------
 20006

$ psql -U analista -d clinica_medica -c "DELETE FROM pacientes WHERE id = 1"
ERROR:  permission denied for table pacientes
```

> As senhas do script (`...#Dev2026`) são de **desenvolvimento**. Em produção elas são trocadas com `ALTER ROLE ... PASSWORD` e guardadas fora do Git (variáveis de ambiente ou cofre de segredos).

---

## Parte 3: Desafio

### Testes de transação: [`05_transactions.sql`](database/05_transactions.sql)

**Operação crítica:** pagar uma consulta com os créditos da carteira do paciente. São duas escritas que precisam acontecer **juntas**: debitar o saldo e registrar o pagamento. Se só a primeira acontecer, o paciente perde dinheiro sem pagar. Se só a segunda acontecer, a clínica recebe sem debitar.

| Caso | O que acontece | Resultado |
|---|---|---|
| **1. Sucesso** | `BEGIN TRANSACTION`, débito de 350,00 do Bruno, `INSERT` do pagamento e `COMMIT` | Saldo do Bruno: 500,00 → **150,00** e a consulta 6 é paga |
| **2. ROLLBACK manual** | `BEGIN`, zera o saldo da Ana, um `SELECT` mostra **0,00**, depois `ROLLBACK` | O `SELECT` seguinte mostra **1000,00** de novo |
| **3. Falha por saldo insuficiente** | A Carla (saldo 100,00) tenta pagar a consulta 7 (250,00) | A transação é **abortada**: saldo continua **100,00** e não existe pagamento |

O caso 3 usa a função `pagar_consulta_com_credito()`, que:
1. trava a linha da carteira com `SELECT ... FOR UPDATE`, para que dois pagamentos ao mesmo tempo não usem o mesmo saldo;
2. confere o saldo e dispara `RAISE EXCEPTION 'Saldo insuficiente'`, o que **aborta a transação inteira**;
3. só debita e registra o pagamento se houver saldo.

Mesmo se a função tivesse um bug, o `CHECK (saldo >= 0)` da tabela continuaria impedindo saldo negativo. A versão "crua", sem captura do erro, está em [`05b_transacao_falha_demo.sql`](database/05b_transacao_falha_demo.sql):

```
BEGIN TRANSACTION;
UPDATE carteiras SET saldo = saldo - 250.00 WHERE paciente_id = 3;
ERROR:  new row for relation "carteiras" violates check constraint "carteiras_saldo_check"
INSERT INTO pagamentos (consulta_id, valor, forma) VALUES (7, 250.00, 'CREDITO');
ERROR:  current transaction is aborted, commands ignored until end of transaction block
COMMIT;
ROLLBACK                       <- com erro, o COMMIT vira ROLLBACK

SELECT saldo FROM carteiras WHERE paciente_id = 3;
 100.00                        <- dados no estado original
```

### Bônus (NoSQL)

O projeto usa **PostgreSQL** (decisão da Semana 14), então o bônus de sessão de transação do MongoDB (`startSession` / `startTransaction`) não se aplica. O equivalente relacional, com `BEGIN` / `COMMIT` / `ROLLBACK`, `SELECT ... FOR UPDATE` e uma função transacional, está implementado acima.

### Validação automática

O workflow [`validar-banco.yml`](.github/workflows/validar-banco.yml) sobe um PostgreSQL 16 no GitHub Actions a cada push e executa os scripts **na ordem**. Ele falha se:
- algum índice não for usado no `EXPLAIN`;
- o analista conseguir apagar ou alterar dados (testado também com **login real** do usuário `analista`);
- a transação sem saldo alterar algum dado.

---

## Parte 4: Reflexão

### Qual é o impacto de criar índices em excesso em um banco de dados? E por que o princípio do menor privilégio é fundamental para a segurança de um sistema?

**Índices.** Um índice funciona como o índice remissivo de um livro: em vez de ler todas as páginas, o banco vai direto ao ponto. Neste projeto, a busca por e-mail ficou cerca de 90 vezes mais rápida. Mas o índice **não é de graça**:

- **Toda escrita fica mais lenta.** Cada `INSERT`, `UPDATE` ou `DELETE` precisa atualizar a tabela **e todos os índices dela**. Uma tabela com 10 índices faz 11 escritas a cada consulta agendada. Em sistemas com muita escrita, como agendamentos, pagamentos ou logs, o excesso de índices vira o gargalo.
- **Gastam espaço** em disco e em memória. Só os dois índices deste projeto ocupam 3,2 MB para 80 mil linhas. Índices que ocupam a memória (cache) tiram espaço dos dados mais usados.
- **Manutenção e backup** ficam maiores e mais lentos, e o otimizador tem mais planos para avaliar.
- **Índices redundantes** não trazem ganho nenhum. Neste projeto, ao rodar o `EXPLAIN`, vimos que o relatório de consultas realizadas já era atendido por um índice existente. Criar outro só aumentaria o custo de escrita.

Por isso, índices devem ser criados **com base nas consultas frequentes reais**, comprovados com `EXPLAIN`, e revisados periodicamente (`pg_stat_user_indexes` mostra quais nunca são usados).

**Menor privilégio.** O princípio diz que cada usuário ou sistema deve ter **apenas as permissões necessárias para sua função, e nada além disso**. Ele é fundamental porque:

- **Limita o estrago de erros humanos.** Se um estagiário com acesso de analista rodar por engano `DELETE FROM pacientes`, o banco responde `permission denied` em vez de apagar o cadastro de todos os pacientes da clínica. Como demonstrado na Parte 2, o erro é barrado pelo próprio banco.
- **Limita o estrago de ataques.** Se a aplicação for invadida, por exemplo com SQL Injection, o atacante tem apenas os poderes do `app_user`. Ele não consegue apagar tabelas nem dados, e muito menos criar usuários, o que poderia fazer se a aplicação se conectasse como `postgres`.
- **Protege dados sensíveis.** Prontuários são dados de saúde (LGPD). Quanto menos pessoas e sistemas puderem alterá-los, menor o risco de vazamento ou adulteração.
- **Facilita auditoria.** Com papéis separados, fica claro quem pode fazer o quê, e cada ação pode ser rastreada até o usuário que a executou.

Índices bem escolhidos garantem **desempenho** sem sacrificar as escritas, e permissões restritas garantem **segurança** sem atrapalhar o trabalho de cada um. Os dois são a base da governança de dados de um sistema em produção.

---

## Roteiro do pitch (3 minutos)

| Tempo | Assunto | O que mostrar |
|---|---|---|
| 0:00 a 0:30 | **Contexto** | Clínica médica em PostgreSQL: modelo em 3FN da Semana 15, agora implementado. Estrutura `01` a `05`. |
| 0:30 a 1:00 | **DDL + DML** | Constraints (PK, FK, NOT NULL, UNIQUE, CHECK) e a tabela de contagem de registros. |
| 1:00 a 1:45 | **Índices** | `EXPLAIN` antes (Seq Scan, 20 mil linhas) e depois (Index Scan, 1 linha): cerca de 90× mais rápido. Contar o caso do índice que seria redundante. |
| 1:45 a 2:20 | **Segurança** | Tabela de papéis. Login como `analista`: `DELETE` dá `permission denied`. |
| 2:20 a 2:50 | **Transações** | Caso 1 (COMMIT), caso 2 (ROLLBACK) e caso 3 (saldo insuficiente aborta tudo e o saldo continua 100,00). |
| 2:50 a 3:00 | **Fechamento** | Pipeline verde no GitHub Actions: tudo é testado automaticamente a cada push. |

# Liga FACOM Fantasy

Trabalho Prático de Laboratório de Banco de Dados (FACOM/UFMS, 2026/2).
Banco de dados PostgreSQL 16 de um *fantasy game* inspirado no Cartola FC, alimentado com dados reais do Brasileirão 2026.

<!-- TODO: confira cada item marcado como TODO antes de entregar e apague estes comentários. -->

## Integrantes

| Nome completo | RGA | Curso |
|---|---|---|
| Erik Kenzo Oikawa | 202519060023 | Engenharia de Software |
| Mateus Suegama Mizukami | 202519060511 | Engenharia de Software |


## Vídeo

<!-- TODO: colocar o link do vídeo (máx. 10 min, sem cortes, com todos os integrantes). -->
Link: <!-- TODO -->

## Estrutura do repositório

| Pasta/arquivo | Conteúdo |
|---|---|
| `docs/der.drawio.png` | Diagrama ER (notação de Chen) |
| `docs/Mapeamento.pdf` | Mapeamento relacional |
| `sql/01-ddl.sql` | Cria o esquema `liga_facom` e todas as tabelas |
| `sql/02-dados.sql` | Dados que não vêm da API: tipos de scout, técnicos, ligas e participações |
| `sql/03-programacao.sql` | Funções, gatilhos e procedimentos em PL/pgSQL |
| `sql/04-consultas.sql` | Visões e consultas (a) a (k) |
| `sql/05-seguranca-indices.sql` | Índices (e segurança, se houver) |
| `carga/carga.py` | Programa de carga (Python) a partir da API do Cartola |
| `carga/json/` | Respostas da API salvas em `.json` |
| `app/` | Aplicação de terminal |

## Pré-requisitos

- Docker (ou PostgreSQL 16+ instalado)
- Python 3.10+ com as bibliotecas `psycopg2-binary` e `requests`
<!-- TODO: incluir aqui o que a aplicação (app/) exigir, na linguagem escolhida. -->

```bash
pip install psycopg2-binary requests
```

## 1. Subindo o banco

```bash
docker run --name liga-facom-pg \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=liga_facom \
  -p 5432:5432 -d postgres:16
```

String de conexão usada nos exemplos abaixo:

```bash
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/liga_facom"
```

<!-- TODO: se usarem outro contêiner/usuário/senha, ajuste os comandos. -->

## 2. Ordem de execução dos scripts

Sempre comece do passo 1 em um banco vazio. O `01-ddl.sql` recria o esquema `liga_facom` (apaga o que existir nele), e o `02-dados.sql` não pode ser executado duas vezes seguidas (e-mails de técnicos são únicos).

| Passo | Comando | Por que nesta posição |
|---|---|---|
| 1 | `sql/01-ddl.sql` | Cria o esquema e as tabelas |
| 2 | `sql/02-dados.sql` | A carga precisa dos tipos de scout (`tipo_scout`) já cadastrados |
| 3 | `carga/carga.py` | Insere clubes, atletas, partidas e scouts reais |
| 4 | `sql/03-programacao.sql` | Cria funções, gatilhos e procedimentos |
| 5 | `sql/04-consultas.sql` | As visões usam as funções criadas no passo 4 |
| 6 | `sql/05-seguranca-indices.sql` | Índices sobre as tabelas já populadas |

<!-- TODO: esta é a ordem que funciona com os arquivos atuais. Se a carga for alterada
     para rodar depois do 03 (necessário para poder executá-la duas vezes), atualize a tabela. -->

Executando cada script e parando no primeiro erro:

```bash
for f in sql/01-ddl.sql sql/02-dados.sql; do
  docker exec -i liga-facom-pg psql -U postgres -d liga_facom -v ON_ERROR_STOP=1 < "$f" || exit 1
done

python carga/carga.py --rodadas 1-10

for f in sql/03-programacao.sql sql/04-consultas.sql sql/05-seguranca-indices.sql; do
  docker exec -i liga-facom-pg psql -U postgres -d liga_facom -v ON_ERROR_STOP=1 < "$f" || exit 1
done
```

No Windows (PowerShell), troque `< "$f"` por `Get-Content $f | docker exec -i ...`.

## 3. Programa de carga

```bash
python carga/carga.py --rodadas 1-10
```

- `--rodadas`: rodadas já jogadas a importar (mínimo 10). Exemplos: `1-10`, `1-5,7-11`.
- `--dsn` ou a variável `DATABASE_URL`: conexão com o PostgreSQL.
- As respostas da API são salvas em `carga/json/`. Faz no máximo uma requisição por segundo.
- Todas as inserções usam consultas parametrizadas e `ON CONFLICT`.

<!-- TODO: descreva aqui, depois de corrigir a carga:
     - se ela lê os .json salvos (modo offline) ou sempre consulta a API;
     - o que acontece ao executá-la duas vezes (deve ser sem erro e sem duplicar);
     - de onde vêm o preço inicial dos atletas e a rodada aberta. -->

## 4. Aplicação

<!-- TODO: preencher quando a aplicação existir. Informe:
     - linguagem e por que foi escolhida;
     - como instalar dependências e como executar (comando exato);
     - menu: técnico (cadastro, escolher técnico, criar/entrar em liga, mercado,
       escalação, confirmação, ranking) e administrador (abrir, fechar e consolidar rodada). -->

```bash
# TODO: comando para executar a aplicação
```

As regras de negócio (orçamento, esquema, capitão, situação do atleta, estado da rodada) ficam no banco. A aplicação envia o pedido e exibe a mensagem de erro retornada pelo banco.

## 5. Fluxo de uma rodada pelo administrador (SQL)

<!-- TODO: confira estes passos em um banco vazio antes de entregar. -->

```sql
SET search_path TO liga_facom;
CALL prc_abrir_rodada(11);      -- abre a rodada (técnicos montam as escalações)
CALL prc_fechar_rodada(11);     -- fecha o mercado
-- carregar as estatísticas da rodada (carga)
CALL prc_consolidar_rodada(11); -- pontuação, valorização, patrimônio e consolidação
```

Confirmação de escalação: `CALL prc_confirma_escalacao(<tecnico_id>, <rodada>);`
Entrada em liga: `CALL prc_entrar_liga(<tecnico_id>, <liga_id>, '<codigo>');`

## 6. Decisões de projeto

<!-- TODO: ajuste conforme a versão final do DDL e do 03. -->

- **Chaves da API:** ids de clube, atleta e partida do Cartola são usados como chave primária.
- **Pontuação do atleta não é armazenada:** é calculada pela função `f_pontos_atleta` a partir dos scouts (evita inconsistência). Um gatilho impede alterar dados de rodada consolidada.
- **Preços:** `historico_preco.preco` é o preço de compra na rodada; `preco_apos_rodada` é o preço calculado na consolidação.
- **Valores em cartoletas e pontos** usam `NUMERIC`, nunca ponto flutuante.
- **Regras no banco:** o que cabe em `CHECK`, `UNIQUE`, `NOT NULL` ou `DEFAULT` está no DDL; o restante, em gatilhos e procedimentos do `03-programacao.sql`.

## 7. Requisitos atendidos

<!-- TODO: listar item a item (1 a 8 do enunciado) se foi atendido total ou parcialmente. -->

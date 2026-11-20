-- Liga FACOM Fantasy
-- DDL limpo e organizado para PostgreSQL 16+.
-- Os IDs de clube, atleta e partida são preservados conforme a API do Cartola.
-- tecnico.id e liga.id usam GENERATED ALWAYS: INSERTs devem omitir essas colunas.
-- Para recuperar um registro, referencie-o por atributo único (ex.: email de técnico)
-- em vez de presumir valores fixos para os IDs.
-- Posição e situação são armazenadas por siglas/textos; o programa de carga
-- deve converter os IDs da API para as siglas/valores usados nos CHECKs.
-- NUMERIC é usado para cartoletas e pontuações para evitar erros de representação
-- binária e arredondamento comuns em REAL/DOUBLE PRECISION.

-- ATENÇÃO: este script recria o schema do zero e APAGA todos os dados de liga_facom.
-- Isso permite executar o DDL novamente durante os testes. Não use em banco com dados
-- que precisem ser preservados.
DROP SCHEMA IF EXISTS liga_facom CASCADE;
CREATE SCHEMA liga_facom;

SET search_path TO liga_facom;

-- Política referencial geral: ON UPDATE RESTRICT em todas as FKs porque as chaves
-- (IDs da API, números de rodada, siglas e nomes de esquema) são identificadores
-- estáveis e não devem ser alterados depois de referenciados. ON DELETE é definido
-- individualmente abaixo: RESTRICT preserva histórico; CASCADE remove registros
-- dependentes que não têm significado sem o registro-pai.

-- TIPOS NUMÉRICOS: pontos e cartoletas usam NUMERIC, porque ponto flutuante não representa
-- exatamente e acumula erro de arredondamento nas somas de pontos e nos cálculos de patrimônio.

-- Cadastro de atletas da API. Posição e situação usam códigos textuais mapeados pela carga.
-- atleta.situacao_atual 'nulo' é um estado do jogo para "sem previsão de jogar". É o padrão para atletas sem dados na carga.
CREATE TABLE liga_facom.atleta (
    id integer NOT NULL,
    nome_completo character varying(100) NOT NULL,
    apelido character varying(50) NOT NULL,
    posicao character varying(3) NOT NULL,
    situacao_atual character varying(15) DEFAULT 'nulo'::character varying NOT NULL,
    CONSTRAINT atleta_posicao_check CHECK (((posicao)::text = ANY ((ARRAY['gol'::character varying, 'lat'::character varying, 'zag'::character varying, 'mei'::character varying, 'ata'::character varying, 'tec'::character varying])::text[]))),
    CONSTRAINT atleta_situacao_atual_check CHECK (((situacao_atual)::text = ANY ((ARRAY['provavel'::character varying, 'duvida'::character varying, 'suspenso'::character varying, 'contundido'::character varying, 'nulo'::character varying])::text[])))
);

-- Histórico do clube ao qual cada atleta pertence em cada rodada.
-- PK sem clube_id: o atleta está em um único clube por rodada. 
CREATE TABLE liga_facom.atleta_clube_rodada (
    atleta_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    clube_id integer NOT NULL
);

-- Participação do atleta em uma partida, incluindo se entrou em campo.
-- RESTRICT em atleta e partida, pois o desempenho é histórico. É entidade fraca entao PK (atleta_id, partida_id).
CREATE TABLE liga_facom.atleta_partida (
    atleta_id integer NOT NULL,
    partida_id integer NOT NULL,
    entrou_em_campo boolean DEFAULT false NOT NULL
);

-- Quantidade de cada scout registrada para um atleta em uma partida.
-- FK: só existe scout de atleta que tem registro naquela partida. 
-- RESTRICT: estatísticas são histórico. 
CREATE TABLE liga_facom.atleta_partida_scout (
    atleta_id integer NOT NULL,
    partida_id integer NOT NULL,
    sigla_scout character varying(10) NOT NULL,
    quantidade integer NOT NULL,
    CONSTRAINT atleta_partida_scout_quantidade_check CHECK ((quantidade >= 0))
);

-- Clubes do Brasileirão, identificados pelo ID externo da API.
CREATE TABLE liga_facom.clube (
    id integer NOT NULL,
    nome character varying(100) NOT NULL,
    abreviacao character(3) NOT NULL,
    escudo text
);

-- RESTRICT em técnico, rodada e esquema, pois a escalação é histórico de pontuação, não se apaga quem já tem escalações.
-- PK (tecnico_id, rodada_numero) garante no máximo uma escalação por técnico por rodada. O CHECK liga estado e data, confirmada se, e somente
-- se, tem data_confirmacao.
CREATE TABLE liga_facom.escalacao (
    tecnico_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    estado character varying(20) DEFAULT 'em_edicao'::character varying NOT NULL,
    data_confirmacao timestamp without time zone,
    esquema_tatico_nome character varying(10) NOT NULL,
    CONSTRAINT escalacao_check CHECK ((((estado)::text = 'confirmada'::text) = (data_confirmacao IS NOT NULL))),
    CONSTRAINT escalacao_estado_check CHECK (((estado)::text = ANY ((ARRAY['em_edicao'::character varying, 'confirmada'::character varying])::text[])))
);

-- PK (tecnico, rodada, atleta): o mesmo atleta não aparece duas vezes na escalação. 
-- FK composta para escalacao com CASCADE: os itens dependem da escalação. 
-- RESTRICT em atleta: não se apaga atleta que já foi escalado. 
-- preco_pago fica registrado porque o preço do atleta pode mudar. CHECK >= 1.00, pois o preço nunca fica abaixo de $ 1,00.
CREATE TABLE liga_facom.escalacao_atleta (
    tecnico_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    atleta_id integer NOT NULL,
    preco_pago numeric(6,2) NOT NULL,
    is_capitao boolean DEFAULT false NOT NULL,
    CONSTRAINT escalacao_atleta_preco_pago_check CHECK ((preco_pago >= 1.00))
);

-- goleiro e técnico fixos em 1. CHECK de tabela exige total de 11 jogadores de linha e goleiro.
CREATE TABLE liga_facom.esquema_tatico (
    nome character varying(10) NOT NULL,
    qtd_lateral integer NOT NULL,
    qtd_meia integer NOT NULL,
    qtd_atacante integer NOT NULL,
    qtd_tecnico integer NOT NULL,
    qtd_zagueiro integer NOT NULL,
    qtd_goleiro integer NOT NULL,
    CONSTRAINT esquema_tatico_check CHECK ((((((qtd_goleiro + qtd_lateral) + qtd_zagueiro) + qtd_meia) + qtd_atacante) = 11)),
    CONSTRAINT esquema_tatico_qtd_atacante_check CHECK ((qtd_atacante >= 0)),
    CONSTRAINT esquema_tatico_qtd_goleiro_check CHECK ((qtd_goleiro = 1)),
    CONSTRAINT esquema_tatico_qtd_lateral_check CHECK ((qtd_lateral >= 0)),
    CONSTRAINT esquema_tatico_qtd_meia_check CHECK ((qtd_meia >= 0)),
    CONSTRAINT esquema_tatico_qtd_tecnico_check CHECK ((qtd_tecnico = 1)),
    CONSTRAINT esquema_tatico_qtd_zagueiro_check CHECK ((qtd_zagueiro >= 0))
);

-- Histórico do preço de cada atleta por rodada.
-- RESTRICT: o histórico de preços não deve sumir com a exclusão de atleta ou rodada. CHECK >= 1.00, pois o preço nunca fica abaixo de $ 1,00.
CREATE TABLE liga_facom.historico_preco (
    atleta_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    preco numeric(6,2) NOT NULL,
    CONSTRAINT historico_preco_preco_check CHECK ((preco >= 1.00))
);

-- RESTRICT em dono_id porque não se apaga técnico que é dono de liga, senão ela ficaria sem dono.
CREATE TABLE liga_facom.liga (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome character varying(100) NOT NULL,
    descricao text,
    codigo_convite text,
    limite_participantes integer NOT NULL,
    tipo character varying(10) NOT NULL,
    dono_id integer NOT NULL,
    CONSTRAINT liga_limite_participantes_check CHECK ((limite_participantes > 0)),
    CONSTRAINT liga_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['publica'::character varying, 'privada'::character varying])::text[]))),
    CONSTRAINT liga_privada_codigo_check CHECK (tipo <> 'privada' OR codigo_convite IS NOT NULL)
);

-- tecnico_id RESTRICT: não se apaga técnico que participa de liga.
-- liga_id CASCADE: ao apagar a liga, as participações dela deixam de existir.
CREATE TABLE liga_facom.participacao_liga (
    tecnico_id integer NOT NULL,
    liga_id integer NOT NULL,
    data_entrada date DEFAULT CURRENT_DATE NOT NULL
);

-- Partidas do campeonato, com mandante, visitante e placar.
-- RESTRICT nas FKs: partida é dado histórico, não se apaga rodada ou clube que tenham partidas. Placares aceitam NULL até o jogo acontecer (sem DEFAULT 0, para não parecer 0 x 0). 
CREATE TABLE liga_facom.partida (
    id integer NOT NULL,
    local text,
    data_hora timestamp without time zone NOT NULL,
    placar_mandante integer,
    placar_visitante integer,
    valida boolean DEFAULT true NOT NULL,
    rodada_numero integer NOT NULL,
    mandante_id integer NOT NULL,
    visitante_id integer NOT NULL,
    CONSTRAINT partida_check CHECK ((mandante_id <> visitante_id)),
    CONSTRAINT partida_check1 CHECK (((placar_mandante IS NULL) = (placar_visitante IS NULL))),
    CONSTRAINT partida_placar_mandante_check CHECK ((placar_mandante >= 0)),
    CONSTRAINT partida_placar_visitante_check CHECK ((placar_visitante >= 0))
);

-- RESTRICT: o patrimônio por rodada é histórico, não se apaga técnico nem rodada que tenham registros aqui. 
CREATE TABLE liga_facom.patrimonio_rodada (
    tecnico_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    patrimonio numeric(10,2) NOT NULL,
    CONSTRAINT patrimonio_rodada_patrimonio_check CHECK ((patrimonio >= (0)::numeric))
);

-- Rodadas do campeonato e seus estados operacionais.
CREATE TABLE liga_facom.rodada (
    numero integer NOT NULL,
    estado character varying(20) NOT NULL,
    CONSTRAINT rodada_estado_check CHECK (((estado)::text = ANY ((ARRAY['aberta'::character varying, 'fechada'::character varying, 'consolidada'::character varying])::text[]))),
    CONSTRAINT rodada_numero_check CHECK (((numero >= 1) AND (numero <= 38)))
);

-- tecnico.patrimonio_atual: DEFAULT 100.00 para que todo técnico começe com $ 100,00 e CHECK >= 0 para evitar patrimônio ser negativo.
CREATE TABLE liga_facom.tecnico (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    apelido_exibicao character varying(50) NOT NULL,
    data_cadastro date DEFAULT CURRENT_DATE NOT NULL,
    nome_time character varying(50) NOT NULL,
    patrimonio_atual numeric(10,2) DEFAULT 100.00 NOT NULL,
    CONSTRAINT tecnico_patrimonio_atual_check CHECK ((patrimonio_atual >= (0)::numeric))
);

-- Catálogo de scouts e seus valores em pontos.
CREATE TABLE liga_facom.tipo_scout (
    sigla character varying(10) NOT NULL,
    descricao text NOT NULL,
    valor_pontos numeric(4,2) NOT NULL
);

-- Relação entre scouts e posições às quais eles se aplicam.
-- Regra adotada: cada scout deve ter ao menos uma linha nesta tabela. Scout irrestrito
-- deve ter as seis posições (gol, lat, zag, mei, ata, tec). A função de pontuação
-- considera o scout aplicável somente quando existe linha para a posição do atleta.
-- CASCADE em sigla_scout: a tabela só descreve o tipo de scout, se ele for apagado, suas posições não fazem sentido sozinhas. 
-- O CHECK de posicao deve ser idêntico ao de atleta.posicao. 
CREATE TABLE liga_facom.tipo_scout_posicao (
    sigla_scout character varying(10) NOT NULL,
    posicao character varying(3) NOT NULL,
    CONSTRAINT tipo_scout_posicao_posicao_check CHECK (((posicao)::text = ANY ((ARRAY['gol'::character varying, 'lat'::character varying, 'zag'::character varying, 'mei'::character varying, 'ata'::character varying, 'tec'::character varying])::text[])))
);

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_pkey PRIMARY KEY (atleta_id, rodada_numero);

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT atleta_partida_pkey PRIMARY KEY (atleta_id, partida_id);

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT atleta_partida_scout_pkey PRIMARY KEY (atleta_id, partida_id, sigla_scout);

ALTER TABLE ONLY liga_facom.atleta
    ADD CONSTRAINT atleta_pkey PRIMARY KEY (id);

ALTER TABLE ONLY liga_facom.clube
    ADD CONSTRAINT clube_abreviacao_key UNIQUE (abreviacao);

ALTER TABLE ONLY liga_facom.clube
    ADD CONSTRAINT clube_pkey PRIMARY KEY (id);

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT escalacao_atleta_pkey PRIMARY KEY (tecnico_id, rodada_numero, atleta_id);

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_pkey PRIMARY KEY (tecnico_id, rodada_numero);

ALTER TABLE ONLY liga_facom.esquema_tatico
    ADD CONSTRAINT esquema_tatico_pkey PRIMARY KEY (nome);

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT historico_preco_pkey PRIMARY KEY (atleta_id, rodada_numero);

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT liga_codigo_convite_key UNIQUE (codigo_convite);


ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT participacao_liga_pkey PRIMARY KEY (tecnico_id, liga_id);

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_pkey PRIMARY KEY (id);

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT patrimonio_rodada_pkey PRIMARY KEY (tecnico_id, rodada_numero);

ALTER TABLE ONLY liga_facom.rodada
    ADD CONSTRAINT rodada_pkey PRIMARY KEY (numero);

ALTER TABLE ONLY liga_facom.tecnico
    ADD CONSTRAINT tecnico_email_key UNIQUE (email);


ALTER TABLE ONLY liga_facom.tipo_scout
    ADD CONSTRAINT tipo_scout_pkey PRIMARY KEY (sigla);

ALTER TABLE ONLY liga_facom.tipo_scout_posicao
    ADD CONSTRAINT tipo_scout_posicao_pkey PRIMARY KEY (sigla_scout, posicao);

-- no máximo um capitão por escalação 
CREATE UNIQUE INDEX uq_escalacao_um_capitao ON liga_facom.escalacao_atleta USING btree (tecnico_id, rodada_numero) WHERE is_capitao;

-- só as rodadas 'aberta' entram nele e ele é único, então apenas uma rodada fica aberta.
CREATE UNIQUE INDEX uq_rodada_aberta ON liga_facom.rodada USING btree (estado) WHERE ((estado)::text = 'aberta'::text);

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_clube_id_fkey FOREIGN KEY (clube_id) REFERENCES liga_facom.clube(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT atleta_partida_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT atleta_partida_partida_id_fkey FOREIGN KEY (partida_id) REFERENCES liga_facom.partida(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT atleta_partida_scout_atleta_id_partida_id_fkey FOREIGN KEY (atleta_id, partida_id) REFERENCES liga_facom.atleta_partida(atleta_id, partida_id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT atleta_partida_scout_sigla_scout_fkey FOREIGN KEY (sigla_scout) REFERENCES liga_facom.tipo_scout(sigla) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT escalacao_atleta_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT escalacao_atleta_tecnico_id_rodada_numero_fkey FOREIGN KEY (tecnico_id, rodada_numero) REFERENCES liga_facom.escalacao(tecnico_id, rodada_numero) ON UPDATE RESTRICT ON DELETE CASCADE;

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_esquema_tatico_nome_fkey FOREIGN KEY (esquema_tatico_nome) REFERENCES liga_facom.esquema_tatico(nome) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT historico_preco_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT historico_preco_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT liga_dono_id_fkey FOREIGN KEY (dono_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT participacao_liga_liga_id_fkey FOREIGN KEY (liga_id) REFERENCES liga_facom.liga(id) ON UPDATE RESTRICT ON DELETE CASCADE;

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT participacao_liga_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_mandante_id_fkey FOREIGN KEY (mandante_id) REFERENCES liga_facom.clube(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_visitante_id_fkey FOREIGN KEY (visitante_id) REFERENCES liga_facom.clube(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT patrimonio_rodada_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT patrimonio_rodada_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY liga_facom.tipo_scout_posicao
    ADD CONSTRAINT tipo_scout_posicao_sigla_scout_fkey FOREIGN KEY (sigla_scout) REFERENCES liga_facom.tipo_scout(sigla) ON UPDATE RESTRICT ON DELETE CASCADE;


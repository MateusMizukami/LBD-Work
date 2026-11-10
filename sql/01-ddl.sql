--
-- PostgreSQL database dump
--


-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

-- Started on 2026-11-10 17:35:53

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 6 (class 2615 OID 16845)
-- Name: liga_facom; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA liga_facom;


SET default_tablespace = '';

SET default_table_access_method = heap;

-- TIPOS NUMÉRICOS: pontos e cartoletas usam NUMERIC, porque ponto flutuante não representa
-- exatamente e acumula erro de arredondamento nas somas de pontos e nos cálculos de patrimônio.

--
-- TOC entry 222 (class 1259 OID 16874)
-- Name: atleta; Type: TABLE; Schema: liga_facom; Owner: -
--
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


--
-- TOC entry 232 (class 1259 OID 17087)
-- Name: atleta_clube_rodada; Type: TABLE; Schema: liga_facom; Owner: -
--
-- PK sem clube_id: o atleta está em um único clube por rodada. 
CREATE TABLE liga_facom.atleta_clube_rodada (
    atleta_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    clube_id integer NOT NULL
);


--
-- TOC entry 229 (class 1259 OID 17007)
-- Name: atleta_partida; Type: TABLE; Schema: liga_facom; Owner: -
--
-- RESTRICT em atleta e partida, pois o desempenho é histórico. É entidade fraca entao PK (atleta_id, partida_id).
CREATE TABLE liga_facom.atleta_partida (
    atleta_id integer NOT NULL,
    partida_id integer NOT NULL,
    entrou_em_campo boolean DEFAULT false NOT NULL
);


--
-- TOC entry 235 (class 1259 OID 17152)
-- Name: atleta_partida_scout; Type: TABLE; Schema: liga_facom; Owner: -
--
-- FK: só existe scout de atleta que tem registro naquela partida. 
-- RESTRICT: estatísticas são histórico. 
CREATE TABLE liga_facom.atleta_partida_scout (
    atleta_id integer NOT NULL,
    partida_id integer NOT NULL,
    sigla_scout character varying(10) NOT NULL,
    quantidade integer NOT NULL,
    CONSTRAINT atleta_partida_scout_quantidade_check CHECK ((quantidade >= 0))
);


--
-- TOC entry 221 (class 1259 OID 16862)
-- Name: clube; Type: TABLE; Schema: liga_facom; Owner: -
--

CREATE TABLE liga_facom.clube (
    id integer NOT NULL,
    nome character varying(100) NOT NULL,
    abreviacao character(3) NOT NULL,
    escudo text
);


--
-- TOC entry 228 (class 1259 OID 16980)
-- Name: escalacao; Type: TABLE; Schema: liga_facom; Owner: -
--
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


--
-- TOC entry 233 (class 1259 OID 17110)
-- Name: escalacao_atleta; Type: TABLE; Schema: liga_facom; Owner: -
--
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


--
-- TOC entry 224 (class 1259 OID 16897)
-- Name: esquema_tatico; Type: TABLE; Schema: liga_facom; Owner: -
--
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


--
-- TOC entry 234 (class 1259 OID 17133)
-- Name: historico_preco; Type: TABLE; Schema: liga_facom; Owner: -
--
-- RESTRICT: o histórico de preços não deve sumir com a exclusão de atleta ou rodada. CHECK >= 1.00, pois o preço nunca fica abaixo de $ 1,00.
CREATE TABLE liga_facom.historico_preco (
    atleta_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    preco numeric(6,2) NOT NULL,
    CONSTRAINT historico_preco_preco_check CHECK ((preco >= 1.00))
);


--
-- TOC entry 226 (class 1259 OID 16926)
-- Name: liga; Type: TABLE; Schema: liga_facom; Owner: -
--
-- RESTRICT em dono_id porque não se apaga técnico que é dono de liga, senão ela ficaria sem dono.
CREATE TABLE liga_facom.liga (
    id integer NOT NULL,
    nome character varying(100) NOT NULL,
    descricao text,
    codigo_convite text,
    limite_participantes integer NOT NULL,
    tipo character varying(10) NOT NULL,
    dono_id integer NOT NULL,
    CONSTRAINT liga_limite_participantes_check CHECK ((limite_participantes > 0)),
    CONSTRAINT liga_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['publica'::character varying, 'privada'::character varying])::text[])))
);


--
-- TOC entry 230 (class 1259 OID 17050)
-- Name: participacao_liga; Type: TABLE; Schema: liga_facom; Owner: -
--
-- tecnico_id RESTRICT: não se apaga técnico que participa de liga.
-- liga_id CASCADE: ao apagar a liga, as participações dela deixam de existir.
CREATE TABLE liga_facom.participacao_liga (
    tecnico_id integer NOT NULL,
    liga_id integer NOT NULL,
    data_entrada date NOT NULL
);


--
-- TOC entry 227 (class 1259 OID 16947)
-- Name: partida; Type: TABLE; Schema: liga_facom; Owner: -
--
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


--
-- TOC entry 231 (class 1259 OID 17068)
-- Name: patrimonio_rodada; Type: TABLE; Schema: liga_facom; Owner: -
--
-- RESTRICT: o patrimônio por rodada é histórico, não se apaga técnico nem rodada que tenham registros aqui. 
CREATE TABLE liga_facom.patrimonio_rodada (
    tecnico_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    patrimonio numeric(10,2) NOT NULL,
    CONSTRAINT patrimonio_rodada_patrimonio_check CHECK ((patrimonio >= (0)::numeric))
);


--
-- TOC entry 223 (class 1259 OID 16887)
-- Name: rodada; Type: TABLE; Schema: liga_facom; Owner: -
--

CREATE TABLE liga_facom.rodada (
    numero integer NOT NULL,
    estado character varying(20) NOT NULL,
    CONSTRAINT rodada_estado_check CHECK (((estado)::text = ANY ((ARRAY['aberta'::character varying, 'fechada'::character varying, 'consolidada'::character varying])::text[]))),
    CONSTRAINT rodada_numero_check CHECK (((numero >= 1) AND (numero <= 38)))
);


--
-- TOC entry 220 (class 1259 OID 16846)
-- Name: tecnico; Type: TABLE; Schema: liga_facom; Owner: -
--
-- tecnico.patrimonio_atual: DEFAULT 100.00 para que todo técnico começe com $ 100,00 e CHECK >= 0 para evitar patrimônio ser negativo.
CREATE TABLE liga_facom.tecnico (
    id integer NOT NULL,
    nome character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    apelido_exibicao character varying(50) NOT NULL,
    data_cadastro date NOT NULL,
    nome_time character varying(50) NOT NULL,
    patrimonio_atual numeric(10,2) DEFAULT 100.00 NOT NULL,
    CONSTRAINT tecnico_patrimonio_atual_check CHECK ((patrimonio_atual >= (0)::numeric))
);


--
-- TOC entry 225 (class 1259 OID 16916)
-- Name: tipo_scout; Type: TABLE; Schema: liga_facom; Owner: -
--
CREATE TABLE liga_facom.tipo_scout (
    sigla character varying(10) NOT NULL,
    descricao text NOT NULL,
    valor_pontos numeric(4,2) NOT NULL
);


--
-- TOC entry 236 (class 1259 OID 17172)
-- Name: tipo_scout_posicao; Type: TABLE; Schema: liga_facom; Owner: -
--
-- CASCADE em sigla_scout: a tabela só descreve o tipo de scout, se ele for apagado, suas posições não fazem sentido sozinhas. 
-- O CHECK de posicao deve ser idêntico ao de atleta.posicao. 
CREATE TABLE liga_facom.tipo_scout_posicao (
    sigla_scout character varying(10) NOT NULL,
    posicao character varying(3) NOT NULL,
    CONSTRAINT tipo_scout_posicao_posicao_check CHECK (((posicao)::text = ANY ((ARRAY['gol'::character varying, 'lat'::character varying, 'zag'::character varying, 'mei'::character varying, 'ata'::character varying, 'tec'::character varying])::text[])))
);


--
-- TOC entry 5165 (class 0 OID 16874)
-- Dependencies: 222
-- Data for Name: atleta; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5175 (class 0 OID 17087)
-- Dependencies: 232
-- Data for Name: atleta_clube_rodada; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5172 (class 0 OID 17007)
-- Dependencies: 229
-- Data for Name: atleta_partida; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5178 (class 0 OID 17152)
-- Dependencies: 235
-- Data for Name: atleta_partida_scout; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5164 (class 0 OID 16862)
-- Dependencies: 221
-- Data for Name: clube; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5171 (class 0 OID 16980)
-- Dependencies: 228
-- Data for Name: escalacao; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5176 (class 0 OID 17110)
-- Dependencies: 233
-- Data for Name: escalacao_atleta; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5167 (class 0 OID 16897)
-- Dependencies: 224
-- Data for Name: esquema_tatico; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5177 (class 0 OID 17133)
-- Dependencies: 234
-- Data for Name: historico_preco; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5169 (class 0 OID 16926)
-- Dependencies: 226
-- Data for Name: liga; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5173 (class 0 OID 17050)
-- Dependencies: 230
-- Data for Name: participacao_liga; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5170 (class 0 OID 16947)
-- Dependencies: 227
-- Data for Name: partida; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5174 (class 0 OID 17068)
-- Dependencies: 231
-- Data for Name: patrimonio_rodada; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5166 (class 0 OID 16887)
-- Dependencies: 223
-- Data for Name: rodada; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5163 (class 0 OID 16846)
-- Dependencies: 220
-- Data for Name: tecnico; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5168 (class 0 OID 16916)
-- Dependencies: 225
-- Data for Name: tipo_scout; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 5179 (class 0 OID 17172)
-- Dependencies: 236
-- Data for Name: tipo_scout_posicao; Type: TABLE DATA; Schema: liga_facom; Owner: -
--



--
-- TOC entry 4983 (class 2606 OID 17094)
-- Name: atleta_clube_rodada atleta_clube_rodada_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_pkey PRIMARY KEY (atleta_id, rodada_numero);


--
-- TOC entry 4977 (class 2606 OID 17015)
-- Name: atleta_partida atleta_partida_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT atleta_partida_pkey PRIMARY KEY (atleta_id, partida_id);


--
-- TOC entry 4990 (class 2606 OID 17161)
-- Name: atleta_partida_scout atleta_partida_scout_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT atleta_partida_scout_pkey PRIMARY KEY (atleta_id, partida_id, sigla_scout);


--
-- TOC entry 4960 (class 2606 OID 16886)
-- Name: atleta atleta_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta
    ADD CONSTRAINT atleta_pkey PRIMARY KEY (id);


--
-- TOC entry 4956 (class 2606 OID 16873)
-- Name: clube clube_abreviacao_key; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.clube
    ADD CONSTRAINT clube_abreviacao_key UNIQUE (abreviacao);


--
-- TOC entry 4958 (class 2606 OID 16871)
-- Name: clube clube_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.clube
    ADD CONSTRAINT clube_pkey PRIMARY KEY (id);


--
-- TOC entry 4985 (class 2606 OID 17121)
-- Name: escalacao_atleta escalacao_atleta_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT escalacao_atleta_pkey PRIMARY KEY (tecnico_id, rodada_numero, atleta_id);


--
-- TOC entry 4975 (class 2606 OID 16991)
-- Name: escalacao escalacao_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_pkey PRIMARY KEY (tecnico_id, rodada_numero);


--
-- TOC entry 4965 (class 2606 OID 16915)
-- Name: esquema_tatico esquema_tatico_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.esquema_tatico
    ADD CONSTRAINT esquema_tatico_pkey PRIMARY KEY (nome);


--
-- TOC entry 4988 (class 2606 OID 17141)
-- Name: historico_preco historico_preco_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT historico_preco_pkey PRIMARY KEY (atleta_id, rodada_numero);


--
-- TOC entry 4969 (class 2606 OID 16941)
-- Name: liga liga_codigo_convite_key; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT liga_codigo_convite_key UNIQUE (codigo_convite);


--
-- TOC entry 4971 (class 2606 OID 16939)
-- Name: liga liga_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT liga_pkey PRIMARY KEY (id);


--
-- TOC entry 4979 (class 2606 OID 17057)
-- Name: participacao_liga participacao_liga_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT participacao_liga_pkey PRIMARY KEY (tecnico_id, liga_id);


--
-- TOC entry 4973 (class 2606 OID 16964)
-- Name: partida partida_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_pkey PRIMARY KEY (id);


--
-- TOC entry 4981 (class 2606 OID 17076)
-- Name: patrimonio_rodada patrimonio_rodada_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT patrimonio_rodada_pkey PRIMARY KEY (tecnico_id, rodada_numero);


--
-- TOC entry 4962 (class 2606 OID 16895)
-- Name: rodada rodada_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.rodada
    ADD CONSTRAINT rodada_pkey PRIMARY KEY (numero);


--
-- TOC entry 4952 (class 2606 OID 16861)
-- Name: tecnico tecnico_email_key; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.tecnico
    ADD CONSTRAINT tecnico_email_key UNIQUE (email);


--
-- TOC entry 4954 (class 2606 OID 16859)
-- Name: tecnico tecnico_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.tecnico
    ADD CONSTRAINT tecnico_pkey PRIMARY KEY (id);


--
-- TOC entry 4967 (class 2606 OID 16925)
-- Name: tipo_scout tipo_scout_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.tipo_scout
    ADD CONSTRAINT tipo_scout_pkey PRIMARY KEY (sigla);


--
-- TOC entry 4992 (class 2606 OID 17179)
-- Name: tipo_scout_posicao tipo_scout_posicao_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.tipo_scout_posicao
    ADD CONSTRAINT tipo_scout_posicao_pkey PRIMARY KEY (sigla_scout, posicao);


--
-- TOC entry 4986 (class 1259 OID 17132)
-- Name: uq_escalacao_um_capitao; Type: INDEX; Schema: liga_facom; Owner: -
--
-- no máximo um capitão por escalação 
CREATE UNIQUE INDEX uq_escalacao_um_capitao ON liga_facom.escalacao_atleta USING btree (tecnico_id, rodada_numero) WHERE is_capitao;


--
-- TOC entry 4963 (class 1259 OID 16896)
-- Name: uq_rodada_aberta; Type: INDEX; Schema: liga_facom; Owner: -
--
-- só as rodadas 'aberta' entram nele e ele é único, então apenas uma rodada fica aberta.
CREATE UNIQUE INDEX uq_rodada_aberta ON liga_facom.rodada USING btree (estado) WHERE ((estado)::text = 'aberta'::text);


--
-- TOC entry 5006 (class 2606 OID 17095)
-- Name: atleta_clube_rodada atleta_clube_rodada_atleta_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5007 (class 2606 OID 17105)
-- Name: atleta_clube_rodada atleta_clube_rodada_clube_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_clube_id_fkey FOREIGN KEY (clube_id) REFERENCES liga_facom.clube(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5008 (class 2606 OID 17100)
-- Name: atleta_clube_rodada atleta_clube_rodada_rodada_numero_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5000 (class 2606 OID 17016)
-- Name: atleta_partida atleta_partida_atleta_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT atleta_partida_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5001 (class 2606 OID 17021)
-- Name: atleta_partida atleta_partida_partida_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT atleta_partida_partida_id_fkey FOREIGN KEY (partida_id) REFERENCES liga_facom.partida(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5013 (class 2606 OID 17167)
-- Name: atleta_partida_scout atleta_partida_scout_atleta_id_partida_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT atleta_partida_scout_atleta_id_partida_id_fkey FOREIGN KEY (atleta_id, partida_id) REFERENCES liga_facom.atleta_partida(atleta_id, partida_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5014 (class 2606 OID 17162)
-- Name: atleta_partida_scout atleta_partida_scout_sigla_scout_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT atleta_partida_scout_sigla_scout_fkey FOREIGN KEY (sigla_scout) REFERENCES liga_facom.tipo_scout(sigla) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5009 (class 2606 OID 17122)
-- Name: escalacao_atleta escalacao_atleta_atleta_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT escalacao_atleta_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5010 (class 2606 OID 17127)
-- Name: escalacao_atleta escalacao_atleta_tecnico_id_rodada_numero_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT escalacao_atleta_tecnico_id_rodada_numero_fkey FOREIGN KEY (tecnico_id, rodada_numero) REFERENCES liga_facom.escalacao(tecnico_id, rodada_numero) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- TOC entry 4997 (class 2606 OID 17002)
-- Name: escalacao escalacao_esquema_tatico_nome_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_esquema_tatico_nome_fkey FOREIGN KEY (esquema_tatico_nome) REFERENCES liga_facom.esquema_tatico(nome) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 4998 (class 2606 OID 16997)
-- Name: escalacao escalacao_rodada_numero_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 4999 (class 2606 OID 16992)
-- Name: escalacao escalacao_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5011 (class 2606 OID 17142)
-- Name: historico_preco historico_preco_atleta_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT historico_preco_atleta_id_fkey FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5012 (class 2606 OID 17147)
-- Name: historico_preco historico_preco_rodada_numero_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT historico_preco_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 4993 (class 2606 OID 16942)
-- Name: liga liga_dono_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT liga_dono_id_fkey FOREIGN KEY (dono_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5002 (class 2606 OID 17063)
-- Name: participacao_liga participacao_liga_liga_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT participacao_liga_liga_id_fkey FOREIGN KEY (liga_id) REFERENCES liga_facom.liga(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- TOC entry 5003 (class 2606 OID 17058)
-- Name: participacao_liga participacao_liga_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT participacao_liga_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 4994 (class 2606 OID 16970)
-- Name: partida partida_mandante_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_mandante_id_fkey FOREIGN KEY (mandante_id) REFERENCES liga_facom.clube(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 4995 (class 2606 OID 16965)
-- Name: partida partida_rodada_numero_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 4996 (class 2606 OID 16975)
-- Name: partida partida_visitante_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_visitante_id_fkey FOREIGN KEY (visitante_id) REFERENCES liga_facom.clube(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5004 (class 2606 OID 17082)
-- Name: patrimonio_rodada patrimonio_rodada_rodada_numero_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT patrimonio_rodada_rodada_numero_fkey FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5005 (class 2606 OID 17077)
-- Name: patrimonio_rodada patrimonio_rodada_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT patrimonio_rodada_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 5015 (class 2606 OID 17180)
-- Name: tipo_scout_posicao tipo_scout_posicao_sigla_scout_fkey; Type: FK CONSTRAINT; Schema: liga_facom; Owner: -
--

ALTER TABLE ONLY liga_facom.tipo_scout_posicao
    ADD CONSTRAINT tipo_scout_posicao_sigla_scout_fkey FOREIGN KEY (sigla_scout) REFERENCES liga_facom.tipo_scout(sigla) ON UPDATE RESTRICT ON DELETE CASCADE;


-- Completed on 2026-11-10 17:35:54

--
-- PostgreSQL database dump complete
--



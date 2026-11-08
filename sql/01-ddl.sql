--
-- PostgreSQL database dump
--

\restrict ucTjCtmrszffTqtH4YPUQwiH1SxuIvmbyUUJSmu5Hplf1Xlhf5Jpaq2w8MkRaYp

-- Dumped from database version 18.6 (Debian 18.6-1.pgdg13+2)
-- Dumped by pg_dump version 18.6

-- Started on 2026-11-08 15:48:18 UTC

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 6 (class 2615 OID 16389)
-- Name: liga_facom; Type: SCHEMA; Schema: -; Owner: lbd
--

CREATE SCHEMA liga_facom;


ALTER SCHEMA liga_facom OWNER TO lbd;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 223 (class 1259 OID 16418)
-- Name: atleta; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.atleta (
    id integer NOT NULL,
    nome_completo character varying(150) NOT NULL,
    apelido character varying(50) NOT NULL,
    posicao character varying(30) NOT NULL,
    situacao_atual character varying(50) NOT NULL
);


ALTER TABLE liga_facom.atleta OWNER TO lbd;

--
-- TOC entry 233 (class 1259 OID 16578)
-- Name: atleta_clube_rodada; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.atleta_clube_rodada (
    atleta_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    clube_id integer NOT NULL
);


ALTER TABLE liga_facom.atleta_clube_rodada OWNER TO lbd;

--
-- TOC entry 236 (class 1259 OID 16642)
-- Name: atleta_partida; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.atleta_partida (
    atleta_id integer NOT NULL,
    partida_id integer NOT NULL,
    entrou_em_campo boolean DEFAULT false NOT NULL
);


ALTER TABLE liga_facom.atleta_partida OWNER TO lbd;

--
-- TOC entry 237 (class 1259 OID 16661)
-- Name: atleta_partida_scout; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.atleta_partida_scout (
    atleta_id integer NOT NULL,
    partida_id integer NOT NULL,
    sigla_scout character varying(10) NOT NULL,
    quantidade integer DEFAULT 0 NOT NULL,
    CONSTRAINT atleta_partida_scout_quantidade_check CHECK ((quantidade >= 0))
);


ALTER TABLE liga_facom.atleta_partida_scout OWNER TO lbd;

--
-- TOC entry 222 (class 1259 OID 16408)
-- Name: clube; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.clube (
    id integer NOT NULL,
    nome character varying(100) NOT NULL,
    abreviacao character varying(10) NOT NULL,
    escudo character varying(255)
);


ALTER TABLE liga_facom.clube OWNER TO lbd;

--
-- TOC entry 230 (class 1259 OID 16516)
-- Name: escalacao; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.escalacao (
    tecnico_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    estado character varying(30) NOT NULL,
    data_confirmacao timestamp without time zone,
    esquema_tatico_nome character varying(10) NOT NULL
);


ALTER TABLE liga_facom.escalacao OWNER TO lbd;

--
-- TOC entry 234 (class 1259 OID 16601)
-- Name: escalacao_atleta; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.escalacao_atleta (
    tecnico_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    atleta_id integer NOT NULL,
    preco_pago numeric(6,2) NOT NULL,
    is_capitao boolean DEFAULT false NOT NULL,
    CONSTRAINT escalacao_atleta_preco_pago_check CHECK ((preco_pago >= (0)::numeric))
);


ALTER TABLE liga_facom.escalacao_atleta OWNER TO lbd;

--
-- TOC entry 225 (class 1259 OID 16436)
-- Name: esquema_tatico; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.esquema_tatico (
    nome character varying(10) NOT NULL,
    qtd_lateral integer NOT NULL,
    qtd_meia integer NOT NULL,
    qtd_atacante integer NOT NULL,
    qtd_tecnicos integer NOT NULL,
    qtd_zagueiro integer NOT NULL,
    qtd_goleiro integer NOT NULL,
    CONSTRAINT esquema_tatico_qtd_atacante_check CHECK ((qtd_atacante >= 0)),
    CONSTRAINT esquema_tatico_qtd_goleiro_check CHECK ((qtd_goleiro >= 0)),
    CONSTRAINT esquema_tatico_qtd_lateral_check CHECK ((qtd_lateral >= 0)),
    CONSTRAINT esquema_tatico_qtd_meia_check CHECK ((qtd_meia >= 0)),
    CONSTRAINT esquema_tatico_qtd_tecnicos_check CHECK ((qtd_tecnicos >= 0)),
    CONSTRAINT esquema_tatico_qtd_zagueiro_check CHECK ((qtd_zagueiro >= 0))
);


ALTER TABLE liga_facom.esquema_tatico OWNER TO lbd;

--
-- TOC entry 235 (class 1259 OID 16623)
-- Name: historico_preco; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.historico_preco (
    atleta_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    preco numeric(6,2) NOT NULL,
    CONSTRAINT historico_preco_preco_check CHECK ((preco >= (0)::numeric))
);


ALTER TABLE liga_facom.historico_preco OWNER TO lbd;

--
-- TOC entry 228 (class 1259 OID 16464)
-- Name: liga; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.liga (
    id integer NOT NULL,
    nome character varying(100) NOT NULL,
    descricao text,
    codigo_convite character varying(30),
    limite_participantes integer,
    tipo character varying(30) NOT NULL,
    dono_id integer NOT NULL,
    CONSTRAINT liga_limite_participantes_check CHECK ((limite_participantes > 0))
);


ALTER TABLE liga_facom.liga OWNER TO lbd;

--
-- TOC entry 227 (class 1259 OID 16463)
-- Name: liga_id_seq; Type: SEQUENCE; Schema: liga_facom; Owner: lbd
--

CREATE SEQUENCE liga_facom.liga_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE liga_facom.liga_id_seq OWNER TO lbd;

--
-- TOC entry 3589 (class 0 OID 0)
-- Dependencies: 227
-- Name: liga_id_seq; Type: SEQUENCE OWNED BY; Schema: liga_facom; Owner: lbd
--

ALTER SEQUENCE liga_facom.liga_id_seq OWNED BY liga_facom.liga.id;


--
-- TOC entry 231 (class 1259 OID 16540)
-- Name: participacao_liga; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.participacao_liga (
    tecnico_id integer NOT NULL,
    liga_id integer NOT NULL,
    data_entrada timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE liga_facom.participacao_liga OWNER TO lbd;

--
-- TOC entry 229 (class 1259 OID 16484)
-- Name: partida; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.partida (
    id integer NOT NULL,
    local character varying(100) NOT NULL,
    data_hora timestamp without time zone NOT NULL,
    placar_mandante integer DEFAULT 0,
    placar_visitante integer DEFAULT 0,
    valida boolean DEFAULT true NOT NULL,
    rodada_numero integer NOT NULL,
    mandante_id integer NOT NULL,
    visitante_id integer NOT NULL,
    CONSTRAINT partida_placar_mandante_check CHECK ((placar_mandante >= 0)),
    CONSTRAINT partida_placar_visitante_check CHECK ((placar_visitante >= 0))
);


ALTER TABLE liga_facom.partida OWNER TO lbd;

--
-- TOC entry 232 (class 1259 OID 16559)
-- Name: patrimonio_rodada; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.patrimonio_rodada (
    tecnico_id integer NOT NULL,
    rodada_numero integer NOT NULL,
    pontuacao_acumulada numeric(8,2) DEFAULT 0.00 NOT NULL
);


ALTER TABLE liga_facom.patrimonio_rodada OWNER TO lbd;

--
-- TOC entry 224 (class 1259 OID 16428)
-- Name: rodada; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.rodada (
    numero integer NOT NULL,
    estado character varying(30) NOT NULL,
    CONSTRAINT rodada_numero_check CHECK (((numero >= 1) AND (numero <= 38)))
);


ALTER TABLE liga_facom.rodada OWNER TO lbd;

--
-- TOC entry 221 (class 1259 OID 16391)
-- Name: tecnico; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.tecnico (
    id integer NOT NULL,
    nome character varying(100) NOT NULL,
    email character varying(150) NOT NULL,
    apelido_exibicao character varying(50) NOT NULL,
    data_cadastro timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    nome_time character varying(50) NOT NULL,
    patrimonio_atual numeric(10,2) DEFAULT 100.00 NOT NULL
);


ALTER TABLE liga_facom.tecnico OWNER TO lbd;

--
-- TOC entry 220 (class 1259 OID 16390)
-- Name: tecnico_id_seq; Type: SEQUENCE; Schema: liga_facom; Owner: lbd
--

CREATE SEQUENCE liga_facom.tecnico_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE liga_facom.tecnico_id_seq OWNER TO lbd;

--
-- TOC entry 3590 (class 0 OID 0)
-- Dependencies: 220
-- Name: tecnico_id_seq; Type: SEQUENCE OWNED BY; Schema: liga_facom; Owner: lbd
--

ALTER SEQUENCE liga_facom.tecnico_id_seq OWNED BY liga_facom.tecnico.id;


--
-- TOC entry 226 (class 1259 OID 16454)
-- Name: tipo_scout; Type: TABLE; Schema: liga_facom; Owner: lbd
--

CREATE TABLE liga_facom.tipo_scout (
    sigla character varying(10) NOT NULL,
    descricao character varying(100) NOT NULL,
    valor_pontos numeric(5,2) NOT NULL,
    posicoes_validas character varying(100) NOT NULL
);


ALTER TABLE liga_facom.tipo_scout OWNER TO lbd;

--
-- TOC entry 3354 (class 2604 OID 16467)
-- Name: liga id; Type: DEFAULT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.liga ALTER COLUMN id SET DEFAULT nextval('liga_facom.liga_id_seq'::regclass);


--
-- TOC entry 3351 (class 2604 OID 16394)
-- Name: tecnico id; Type: DEFAULT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.tecnico ALTER COLUMN id SET DEFAULT nextval('liga_facom.tecnico_id_seq'::regclass);


--
-- TOC entry 3405 (class 2606 OID 16585)
-- Name: atleta_clube_rodada atleta_clube_rodada_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT atleta_clube_rodada_pkey PRIMARY KEY (atleta_id, rodada_numero);


--
-- TOC entry 3411 (class 2606 OID 16650)
-- Name: atleta_partida atleta_partida_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT atleta_partida_pkey PRIMARY KEY (atleta_id, partida_id);


--
-- TOC entry 3413 (class 2606 OID 16671)
-- Name: atleta_partida_scout atleta_partida_scout_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT atleta_partida_scout_pkey PRIMARY KEY (atleta_id, partida_id, sigla_scout);


--
-- TOC entry 3385 (class 2606 OID 16427)
-- Name: atleta atleta_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta
    ADD CONSTRAINT atleta_pkey PRIMARY KEY (id);


--
-- TOC entry 3381 (class 2606 OID 16417)
-- Name: clube clube_abreviacao_key; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.clube
    ADD CONSTRAINT clube_abreviacao_key UNIQUE (abreviacao);


--
-- TOC entry 3383 (class 2606 OID 16415)
-- Name: clube clube_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.clube
    ADD CONSTRAINT clube_pkey PRIMARY KEY (id);


--
-- TOC entry 3407 (class 2606 OID 16612)
-- Name: escalacao_atleta escalacao_atleta_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT escalacao_atleta_pkey PRIMARY KEY (tecnico_id, rodada_numero, atleta_id);


--
-- TOC entry 3399 (class 2606 OID 16524)
-- Name: escalacao escalacao_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT escalacao_pkey PRIMARY KEY (tecnico_id, rodada_numero);


--
-- TOC entry 3389 (class 2606 OID 16453)
-- Name: esquema_tatico esquema_tatico_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.esquema_tatico
    ADD CONSTRAINT esquema_tatico_pkey PRIMARY KEY (nome);


--
-- TOC entry 3409 (class 2606 OID 16631)
-- Name: historico_preco historico_preco_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT historico_preco_pkey PRIMARY KEY (atleta_id, rodada_numero);


--
-- TOC entry 3393 (class 2606 OID 16478)
-- Name: liga liga_codigo_convite_key; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT liga_codigo_convite_key UNIQUE (codigo_convite);


--
-- TOC entry 3395 (class 2606 OID 16476)
-- Name: liga liga_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT liga_pkey PRIMARY KEY (id);


--
-- TOC entry 3401 (class 2606 OID 16548)
-- Name: participacao_liga participacao_liga_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT participacao_liga_pkey PRIMARY KEY (tecnico_id, liga_id);


--
-- TOC entry 3397 (class 2606 OID 16500)
-- Name: partida partida_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT partida_pkey PRIMARY KEY (id);


--
-- TOC entry 3403 (class 2606 OID 16567)
-- Name: patrimonio_rodada patrimonio_rodada_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT patrimonio_rodada_pkey PRIMARY KEY (tecnico_id, rodada_numero);


--
-- TOC entry 3387 (class 2606 OID 16435)
-- Name: rodada rodada_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.rodada
    ADD CONSTRAINT rodada_pkey PRIMARY KEY (numero);


--
-- TOC entry 3377 (class 2606 OID 16407)
-- Name: tecnico tecnico_email_key; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.tecnico
    ADD CONSTRAINT tecnico_email_key UNIQUE (email);


--
-- TOC entry 3379 (class 2606 OID 16405)
-- Name: tecnico tecnico_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.tecnico
    ADD CONSTRAINT tecnico_pkey PRIMARY KEY (id);


--
-- TOC entry 3391 (class 2606 OID 16462)
-- Name: tipo_scout tipo_scout_pkey; Type: CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.tipo_scout
    ADD CONSTRAINT tipo_scout_pkey PRIMARY KEY (sigla);


--
-- TOC entry 3425 (class 2606 OID 16586)
-- Name: atleta_clube_rodada fk_acr_atleta; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT fk_acr_atleta FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3426 (class 2606 OID 16596)
-- Name: atleta_clube_rodada fk_acr_clube; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT fk_acr_clube FOREIGN KEY (clube_id) REFERENCES liga_facom.clube(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3427 (class 2606 OID 16591)
-- Name: atleta_clube_rodada fk_acr_rodada; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_clube_rodada
    ADD CONSTRAINT fk_acr_rodada FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3432 (class 2606 OID 16651)
-- Name: atleta_partida fk_ap_atleta; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT fk_ap_atleta FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3433 (class 2606 OID 16656)
-- Name: atleta_partida fk_ap_partida; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_partida
    ADD CONSTRAINT fk_ap_partida FOREIGN KEY (partida_id) REFERENCES liga_facom.partida(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3434 (class 2606 OID 16672)
-- Name: atleta_partida_scout fk_aps_atleta; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT fk_aps_atleta FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3435 (class 2606 OID 16677)
-- Name: atleta_partida_scout fk_aps_partida; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT fk_aps_partida FOREIGN KEY (partida_id) REFERENCES liga_facom.partida(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3436 (class 2606 OID 16682)
-- Name: atleta_partida_scout fk_aps_scout; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.atleta_partida_scout
    ADD CONSTRAINT fk_aps_scout FOREIGN KEY (sigla_scout) REFERENCES liga_facom.tipo_scout(sigla) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3428 (class 2606 OID 16618)
-- Name: escalacao_atleta fk_esca_atleta; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT fk_esca_atleta FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3429 (class 2606 OID 16613)
-- Name: escalacao_atleta fk_esca_escalacao; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.escalacao_atleta
    ADD CONSTRAINT fk_esca_escalacao FOREIGN KEY (tecnico_id, rodada_numero) REFERENCES liga_facom.escalacao(tecnico_id, rodada_numero) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3418 (class 2606 OID 16535)
-- Name: escalacao fk_escalacao_esquema; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT fk_escalacao_esquema FOREIGN KEY (esquema_tatico_nome) REFERENCES liga_facom.esquema_tatico(nome) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3419 (class 2606 OID 16530)
-- Name: escalacao fk_escalacao_rodada; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT fk_escalacao_rodada FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3420 (class 2606 OID 16525)
-- Name: escalacao fk_escalacao_tecnico; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.escalacao
    ADD CONSTRAINT fk_escalacao_tecnico FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3430 (class 2606 OID 16632)
-- Name: historico_preco fk_hp_atleta; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT fk_hp_atleta FOREIGN KEY (atleta_id) REFERENCES liga_facom.atleta(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3431 (class 2606 OID 16637)
-- Name: historico_preco fk_hp_rodada; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.historico_preco
    ADD CONSTRAINT fk_hp_rodada FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3414 (class 2606 OID 16479)
-- Name: liga fk_liga_tecnico; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.liga
    ADD CONSTRAINT fk_liga_tecnico FOREIGN KEY (dono_id) REFERENCES liga_facom.tecnico(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3421 (class 2606 OID 16554)
-- Name: participacao_liga fk_part_liga; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT fk_part_liga FOREIGN KEY (liga_id) REFERENCES liga_facom.liga(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3422 (class 2606 OID 16549)
-- Name: participacao_liga fk_part_tecnico; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.participacao_liga
    ADD CONSTRAINT fk_part_tecnico FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3415 (class 2606 OID 16506)
-- Name: partida fk_partida_mandante; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT fk_partida_mandante FOREIGN KEY (mandante_id) REFERENCES liga_facom.clube(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3416 (class 2606 OID 16501)
-- Name: partida fk_partida_rodada; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT fk_partida_rodada FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3417 (class 2606 OID 16511)
-- Name: partida fk_partida_visitante; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.partida
    ADD CONSTRAINT fk_partida_visitante FOREIGN KEY (visitante_id) REFERENCES liga_facom.clube(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3423 (class 2606 OID 16573)
-- Name: patrimonio_rodada fk_patrimonio_rodada; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT fk_patrimonio_rodada FOREIGN KEY (rodada_numero) REFERENCES liga_facom.rodada(numero) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 3424 (class 2606 OID 16568)
-- Name: patrimonio_rodada fk_patrimonio_tecnico; Type: FK CONSTRAINT; Schema: liga_facom; Owner: lbd
--

ALTER TABLE ONLY liga_facom.patrimonio_rodada
    ADD CONSTRAINT fk_patrimonio_tecnico FOREIGN KEY (tecnico_id) REFERENCES liga_facom.tecnico(id) ON UPDATE CASCADE ON DELETE CASCADE;


-- Completed on 2026-11-08 15:48:18 UTC

--
-- PostgreSQL database dump complete
--

\unrestrict ucTjCtmrszffTqtH4YPUQwiH1SxuIvmbyUUJSmu5Hplf1Xlhf5Jpaq2w8MkRaYp


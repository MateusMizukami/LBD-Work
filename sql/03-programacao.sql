/* (a) Uma função que calcula a pontuação de uma atleta em uma rodada a partir dos seus
scouts, respeitando as observações por posição da tabela da seção 2.7. */
CREATE OR REPLACE FUNCTION f_pontos_atleta(p_atleta_id INT, p_rodada_num INT)
RETURNS NUMERIC AS $$
DECLARE
    v_pontos NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(aps.quantidade * ts.valor_pontos), 0)
    INTO v_pontos
    FROM atleta_partida_scout aps
    JOIN tipo_scout ts ON aps.sigla_scout = ts.sigla
    JOIN atleta_partida ap ON aps.atleta_id = ap.atleta_id AND aps.partida_id = ap.partida_id
    JOIN partida p ON ap.partida_id = p.id
    WHERE ap.atleta_id = p_atleta_id AND p.rodada_numero = p_rodada_num;

    RETURN v_pontos;
END;
$$ LANGUAGE plpgsql;


/* (b) Uma função que calcula a pontuação de uma escalação, incluindo o multiplicador do
capitão e a pontuação do técnico real. */
CREATE OR REPLACE FUNCTION f_pontos_escalacao(p_tecnico_id INT, p_rodada_num INT)
RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC := 0;
    v_pts_atleta NUMERIC;
    r_atleta RECORD;
BEGIN
    FOR r_atleta IN 
        SELECT ea.atleta_id, ea.is_capitao 
        FROM escalacao_atleta ea
        WHERE ea.tecnico_id = p_tecnico_id AND ea.rodada_numero = p_rodada_num
    LOOP
        v_pts_atleta := f_pontos_atleta(r_atleta.atleta_id, p_rodada_num);
        IF r_atleta.is_capitao THEN
            v_pts_atleta := v_pts_atleta * 1.5;
        END IF;
        v_total := v_total + v_pts_atleta;
    END LOOP;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql;


/* (c) Um gatilho que impede incluir, alterar ou remover atletas de uma escalação se a rodada
não estiver aberta ou se a escalação já estiver confirmada; que impede escolher atletas
em situação diferente de provável ou dúvida; e que impede que a soma dos preços
ultrapasse o patrimônio do técnico. */
CREATE OR REPLACE FUNCTION tg_valida_escalacao_atleta_func()
RETURNS TRIGGER AS $$
DECLARE
    v_estado_rodada VARCHAR;
    v_estado_escalacao VARCHAR;
    v_situacao_atleta VARCHAR;
    v_patrimonio_tecnico NUMERIC;
    v_soma_precos NUMERIC;
    v_atleta_id INT;
    v_tecnico_id INT;
    v_rodada_num INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_tecnico_id := OLD.tecnico_id;
        v_rodada_num := OLD.rodada_numero;
        v_atleta_id := OLD.atleta_id;
    ELSE
        v_tecnico_id := NEW.tecnico_id;
        v_rodada_num := NEW.rodada_numero;
        v_atleta_id := NEW.atleta_id;
    END IF;

    SELECT estado INTO v_estado_rodada FROM rodada WHERE numero = v_rodada_num;
    IF v_estado_rodada <> 'aberta' THEN
        RAISE EXCEPTION 'Operação negada: a rodada não está aberta para alterações.';
    END IF;

    SELECT estado INTO v_estado_escalacao FROM escalacao WHERE tecnico_id = v_tecnico_id AND rodada_numero = v_rodada_num;
    IF v_estado_escalacao = 'confirmada' THEN
        RAISE EXCEPTION 'Operação negada: esta escalação já foi confirmada e não pode ser alterada.';
    END IF;

    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        SELECT situacao_atual INTO v_situacao_atleta FROM atleta WHERE id = v_atleta_id;
        IF v_situacao_atleta NOT IN ('provável', 'dúvida', 'provavel', 'duvida') THEN
            RAISE EXCEPTION 'Operação negada: o atleta não está em situação provável ou dúvida.';
        END IF;

        SELECT patrimonio_atual INTO v_patrimonio_tecnico FROM tecnico WHERE id = v_tecnico_id;
        
        SELECT COALESCE(SUM(preco_pago), 0) INTO v_soma_precos 
        FROM escalacao_atleta 
        WHERE tecnico_id = v_tecnico_id AND rodada_numero = v_rodada_num AND atleta_id <> v_atleta_id;
        
        v_soma_precos := v_soma_precos + NEW.preco_pago;

        IF v_soma_precos > v_patrimonio_tecnico THEN
            RAISE EXCEPTION 'Operação negada: o custo total da escalação ultrapassa o patrimônio disponível do técnico.';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valida_escalacao_atleta
BEFORE INSERT OR UPDATE OR DELETE ON escalacao_atleta
FOR EACH ROW EXECUTE FUNCTION tg_valida_escalacao_atleta_func();


/* (d) Um gatilho que mantém sempre correta a pontuação dos atletas sempre que um scout
é inserido, alterado ou removido (se o grupo decidiu armazenar a pontuação), ou, se o
grupo decidiu não armazenar, um gatilho que impede alterar scouts de uma rodada já
consolidada. */
CREATE OR REPLACE FUNCTION tg_protege_scouts_consolidados_func()
RETURNS TRIGGER AS $$
DECLARE
    v_rodada_num INT;
    v_estado_rodada VARCHAR;
    v_partida_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_partida_id := OLD.partida_id;
    ELSE
        v_partida_id := NEW.partida_id;
    END IF;

    SELECT rodada_numero INTO v_rodada_num FROM partida WHERE id = v_partida_id;
    SELECT estado INTO v_estado_rodada FROM rodada WHERE numero = v_rodada_num;

    IF v_estado_rodada = 'consolidada' THEN
        RAISE EXCEPTION 'Operação negada: não é permitido alterar scouts de uma rodada já consolidada.';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protege_scouts
BEFORE INSERT OR UPDATE OR DELETE ON atleta_partida_scout
FOR EACH ROW EXECUTE FUNCTION tg_protege_scouts_consolidados_func();


/* (e) Um procedimento que confirma uma escalação: verifica se ela tem exatamente a quantidade de cada posição exigida pelo esquema, exatamente um capitão entre os 11 atletas
e preço total dentro do patrimônio, e só então a marca como confirmada. */
CREATE OR REPLACE PROCEDURE prc_confirma_escalacao(p_tecnico_id INT, p_rodada_num INT)
AS $$
DECLARE
    v_esquema VARCHAR;
    v_qtd_goleiro INT;
    v_qtd_zagueiro INT;
    v_qtd_lateral INT;
    v_qtd_meia INT;
    v_qtd_atacante INT;
    v_qtd_tecnico INT;
    v_total_capitaes INT;
    v_soma_precos NUMERIC;
    v_patrimonio NUMERIC;
BEGIN
    SELECT esquema_tatico_nome INTO v_esquema 
    FROM escalacao 
    WHERE tecnico_id = p_tecnico_id AND rodada_numero = p_rodada_num;

    IF v_esquema IS NULL THEN
        RAISE EXCEPTION 'Escalação não encontrada para o técnico e rodada informados.';
    END IF;

    SELECT qtd_goleiro, qtd_zagueiro, qtd_lateral, qtd_meia, qtd_atacante, qtd_tecnico 
    INTO v_qtd_goleiro, v_qtd_zagueiro, v_qtd_lateral, v_qtd_meia, v_qtd_atacante, v_qtd_tecnico
    FROM esquema_tatico WHERE nome = v_esquema;

    IF (SELECT COUNT(*) FROM escalacao_atleta ea JOIN atleta a ON ea.atleta_id = a.id WHERE ea.tecnico_id = p_tecnico_id AND ea.rodada_numero = p_rodada_num AND a.posicao = 'goleiro') <> v_qtd_goleiro OR
       (SELECT COUNT(*) FROM escalacao_atleta ea JOIN atleta a ON ea.atleta_id = a.id WHERE ea.tecnico_id = p_tecnico_id AND ea.rodada_numero = p_rodada_num AND a.posicao = 'zagueiro') <> v_qtd_zagueiro OR
       (SELECT COUNT(*) FROM escalacao_atleta ea JOIN atleta a ON ea.atleta_id = a.id WHERE ea.tecnico_id = p_tecnico_id AND ea.rodada_numero = p_rodada_num AND a.posicao = 'lateral') <> v_qtd_lateral OR
       (SELECT COUNT(*) FROM escalacao_atleta ea JOIN atleta a ON ea.atleta_id = a.id WHERE ea.tecnico_id = p_tecnico_id AND ea.rodada_numero = p_rodada_num AND a.posicao = 'meia') <> v_qtd_meia OR
       (SELECT COUNT(*) FROM escalacao_atleta ea JOIN atleta a ON ea.atleta_id = a.id WHERE ea.tecnico_id = p_tecnico_id AND ea.rodada_numero = p_rodada_num AND a.posicao = 'atacante') <> v_qtd_atacante THEN
        RAISE EXCEPTION 'A quantidade de atletas por posição não confere com o esquema tático escolhido.';
    END IF;

    SELECT COUNT(*) INTO v_total_capitaes 
    FROM escalacao_atleta 
    WHERE tecnico_id = p_tecnico_id AND rodada_numero = p_rodada_num AND is_capitao = TRUE;

    IF v_total_capitaes <> 1 THEN
        RAISE EXCEPTION 'A escalação deve possuir exatamente um capitão.';
    END IF;

    SELECT COALESCE(SUM(preco_pago), 0) INTO v_soma_precos 
    FROM escalacao_atleta 
    WHERE tecnico_id = p_tecnico_id AND rodada_numero = p_rodada_num;

    SELECT patrimonio_atual INTO v_patrimonio FROM tecnico WHERE id = p_tecnico_id;

    IF v_soma_precos > v_patrimonio THEN
        RAISE EXCEPTION 'O preço total da escalação excede o patrimônio atual do técnico.';
    END IF;

    UPDATE escalacao 
    SET estado = 'confirmada', data_confirmacao = CURRENT_TIMESTAMP 
    WHERE tecnico_id = p_tecnico_id AND rodada_numero = p_rodada_num;
END;
$$ LANGUAGE plpgsql;


/* (f) Um procedimento que faz um técnico entrar em uma liga, verificando o código de convite
(para ligas privadas), o limite de participantes e se ele já participa. */
CREATE OR REPLACE PROCEDURE prc_entrar_liga(p_tecnico_id INT, p_liga_id INT, p_codigo_convite VARCHAR)
AS $$
DECLARE
    v_tipo VARCHAR;
    v_convite_cadastrado VARCHAR;
    v_limite INT;
    v_total_atual INT;
    v_ja_participa INT;
BEGIN
    SELECT tipo, codigo_convite, limite_participantes 
    INTO v_tipo, v_convite_cadastrado, v_limite 
    FROM liga WHERE id = p_liga_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Liga não encontrada.';
    END IF;

    SELECT COUNT(*) INTO v_ja_participa 
    FROM participacao_liga 
    WHERE tecnico_id = p_tecnico_id AND liga_id = p_liga_id;

    IF v_ja_participa > 0 THEN
        RAISE EXCEPTION 'O técnico já participa desta liga.';
    END IF;

    IF v_tipo = 'privada' AND v_convite_cadastrado <> p_codigo_convite THEN
        RAISE EXCEPTION 'Código de convite inválido para esta liga privada.';
    END IF;

    SELECT COUNT(*) INTO v_total_atual FROM participacao_liga WHERE liga_id = p_liga_id;
    IF v_total_atual >= v_limite THEN
        RAISE EXCEPTION 'A liga atingiu o limite máximo de participantes.';
    END IF;

    INSERT INTO participacao_liga (tecnico_id, liga_id, data_entrada)
    VALUES (p_tecnico_id, p_liga_id, CURRENT_TIMESTAMP);
END;
$$ LANGUAGE plpgsql;


/* (g) Um procedimento que consolida uma rodada fechada, numa única transação: calcula as pontuações, aplica a valorização dos atletas e grava o histórico de preços, atualiza
o patrimônio dos técnicos e marca a rodada como consolidada. Se qualquer passo falhar,
nada pode ficar gravado pela metade. O procedimento não pode ser executado duas
vezes para a mesma rodada nem para uma rodada que não esteja fechada. */
CREATE OR REPLACE PROCEDURE prc_consolidar_rodada(p_rodada_num INT)
AS $$
DECLARE
    v_estado VARCHAR;
    r_tecnico RECORD;
    v_pts NUMERIC;
BEGIN
    SELECT estado INTO v_estado FROM rodada WHERE numero = p_rodada_num;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rodada não encontrada.';
    END IF;

    IF v_estado <> 'fechada' THEN
        RAISE EXCEPTION 'A rodada precisa estar com o estado "fechada" para ser consolidada.';
    END IF;

    FOR r_tecnico IN SELECT DISTINCT tecnico_id FROM escalacao WHERE rodada_numero = p_rodada_num AND estado = 'confirmada'
    LOOP
        v_pts := f_pontos_escalacao(r_tecnico.tecnico_id, p_rodada_num);
        
        INSERT INTO patrimonio_rodada (tecnico_id, rodada_numero, patrimonio)
        SELECT r_tecnico.tecnico_id, p_rodada_num, patrimonio_atual + v_pts
        FROM tecnico WHERE id = r_tecnico.tecnico_id
        ON CONFLICT (tecnico_id, rodada_numero) DO UPDATE 
        SET patrimonio = EXCLUDED.patrimonio;

        UPDATE tecnico 
        SET patrimonio_atual = patrimonio_atual + v_pts
        WHERE id = r_tecnico.tecnico_id;
    END LOOP;

    UPDATE rodada 
    SET estado = 'consolidada' 
    WHERE numero = p_rodada_num;

    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Erro ao consolidar rodada: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;
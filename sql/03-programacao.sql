SET search_path TO liga_facom;

-- (a) função que calcula a pontuação individual por scouts válidos para a posição.
CREATE OR REPLACE FUNCTION f_pontos_atleta(p_atleta_id INT, p_rodada_num INT)
RETURNS NUMERIC AS $$
DECLARE
    v_pontos NUMERIC;
BEGIN
    SELECT COALESCE(SUM(aps.quantidade * ts.valor_pontos), 0)
    INTO v_pontos
    FROM atleta_partida_scout aps
    JOIN tipo_scout ts ON ts.sigla = aps.sigla_scout
    JOIN atleta_partida ap ON ap.atleta_id = aps.atleta_id AND ap.partida_id = aps.partida_id
    JOIN partida p ON p.id = ap.partida_id
    JOIN atleta a ON a.id = ap.atleta_id
    JOIN tipo_scout_posicao tsp ON tsp.sigla_scout = ts.sigla AND tsp.posicao = a.posicao
    WHERE ap.atleta_id = p_atleta_id
      AND p.rodada_numero = p_rodada_num
      AND ap.entrou_em_campo
      AND p.valida;

    RETURN v_pontos;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

-- função que calcula a pontuação do técnico com base em resultados de partidas. Sem partida jogada, retorna NULL.
CREATE OR REPLACE FUNCTION f_pontos_tecnico_real(p_atleta_id INT, p_rodada_num INT)
RETURNS NUMERIC AS $$
DECLARE
    v_pontos NUMERIC;
BEGIN
    SELECT CASE
        WHEN p.placar_mandante = p.placar_visitante THEN 2
        WHEN acr.clube_id = p.mandante_id AND p.placar_mandante > p.placar_visitante THEN 5
        WHEN acr.clube_id = p.visitante_id AND p.placar_visitante > p.placar_mandante THEN 5
        ELSE 0
    END
    INTO v_pontos
    FROM atleta_clube_rodada acr
    JOIN partida p ON p.rodada_numero = acr.rodada_numero AND acr.clube_id IN (p.mandante_id, p.visitante_id)
    WHERE acr.atleta_id = p_atleta_id AND acr.rodada_numero = p_rodada_num AND p.valida AND p.placar_mandante IS NOT NULL AND p.placar_visitante IS NOT NULL
    ORDER BY p.id
    LIMIT 1;

    RETURN v_pontos;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

-- (b) função que calcula a pontuação de uma escalação confirmada.
CREATE OR REPLACE FUNCTION f_pontos_escalacao(p_tecnico_id INT, p_rodada_num INT)
RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC := 0;
    v_pts_atleta NUMERIC;
    r_atleta RECORD;
BEGIN
    FOR r_atleta IN
        SELECT ea.atleta_id, ea.is_capitao, a.posicao
        FROM escalacao_atleta ea
        JOIN escalacao e ON e.tecnico_id = ea.tecnico_id AND e.rodada_numero = ea.rodada_numero
        JOIN atleta a ON a.id = ea.atleta_id
        WHERE ea.tecnico_id = p_tecnico_id AND ea.rodada_numero = p_rodada_num AND e.estado = 'confirmada'
    LOOP
        IF r_atleta.posicao = 'tec' THEN
            v_pts_atleta := COALESCE(f_pontos_tecnico_real(r_atleta.atleta_id, p_rodada_num), 0);
        ELSE
            v_pts_atleta := f_pontos_atleta(r_atleta.atleta_id, p_rodada_num);
            IF r_atleta.is_capitao THEN
                v_pts_atleta := v_pts_atleta * 1.5;
            END IF;
        END IF;

        v_total := v_total + v_pts_atleta;
    END LOOP;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

-- (c) Gatilho para validação de alterações nos itens da escalação.
CREATE OR REPLACE FUNCTION tg_valida_escalacao_atleta_func()
RETURNS TRIGGER AS $$
DECLARE
    v_tecnico_id INT;
    v_rodada_num INT;
    v_atleta_anterior INT;
    v_estado_rodada VARCHAR;
    v_estado_escalacao VARCHAR;
    v_situacao VARCHAR;
    v_posicao VARCHAR;
    v_patrimonio NUMERIC;
    v_soma_precos NUMERIC;
    v_preco NUMERIC;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.tecnico_id <> NEW.tecnico_id OR OLD.rodada_numero <> NEW.rodada_numero THEN
            RAISE EXCEPTION 'Não é permitido mover um item para outra escalação.';
        END IF;
        v_atleta_anterior := OLD.atleta_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_tecnico_id := OLD.tecnico_id;
        v_rodada_num := OLD.rodada_numero;
    ELSE
        v_tecnico_id := NEW.tecnico_id;
        v_rodada_num := NEW.rodada_numero;
    END IF;

    SELECT estado INTO v_estado_rodada
    FROM rodada
    WHERE numero = v_rodada_num
    FOR SHARE;

    IF v_estado_rodada IS DISTINCT FROM 'aberta' THEN
        RAISE EXCEPTION 'A rodada não está aberta para alterações.';
    END IF;

    SELECT estado INTO v_estado_escalacao
    FROM escalacao WHERE tecnico_id = v_tecnico_id AND rodada_numero = v_rodada_num
    FOR UPDATE;
    IF v_estado_escalacao = 'confirmada' THEN
        RAISE EXCEPTION 'A escalação já foi confirmada e não pode ser alterada.';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    IF v_estado_escalacao IS NULL THEN
        RAISE EXCEPTION 'Escalação não encontrada.';
    END IF;

    SELECT situacao_atual, posicao INTO v_situacao, v_posicao
    FROM atleta WHERE id = NEW.atleta_id;
    IF NOT FOUND OR v_situacao NOT IN ('provavel', 'duvida') THEN
        RAISE EXCEPTION 'Só é permitido escalar atleta provável ou em dúvida.';
    END IF;
    IF NEW.is_capitao AND v_posicao = 'tec' THEN
        RAISE EXCEPTION 'O técnico real não pode ser capitão.';
    END IF;

    SELECT preco INTO v_preco
    FROM historico_preco
    WHERE atleta_id = NEW.atleta_id AND rodada_numero = v_rodada_num;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Não há preço cadastrado para o atleta % nesta rodada.', NEW.atleta_id;
    END IF;
    IF NEW.preco_pago IS DISTINCT FROM v_preco THEN
        RAISE EXCEPTION 'O preço pago deve ser igual ao preço do atleta nesta rodada.';
    END IF;

    SELECT patrimonio_atual INTO v_patrimonio
    FROM tecnico
    WHERE id = v_tecnico_id;

    SELECT COALESCE(SUM(preco_pago), 0) INTO v_soma_precos
    FROM escalacao_atleta
    WHERE tecnico_id = v_tecnico_id AND rodada_numero = v_rodada_num
    AND atleta_id IS DISTINCT FROM v_atleta_anterior;

    IF v_soma_precos + v_preco > v_patrimonio THEN
        RAISE EXCEPTION 'O custo da escalação ultrapassa o patrimônio disponível.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

CREATE OR REPLACE TRIGGER trg_valida_escalacao_atleta
BEFORE INSERT OR UPDATE OR DELETE ON escalacao_atleta
FOR EACH ROW EXECUTE FUNCTION tg_valida_escalacao_atleta_func();

-- (d) Gatilho que protege os dados que alimentam a pontuação calculada sob demanda.
CREATE OR REPLACE FUNCTION tg_protege_scouts_consolidados_func()
RETURNS TRIGGER AS $$
DECLARE
    v_partida_antiga INT;
    v_partida_nova INT;
    v_rodada_antiga INT;
    v_rodada_nova INT;
    v_estado VARCHAR;
BEGIN
    IF TG_TABLE_NAME IN ('partida', 'atleta_clube_rodada') THEN
        IF TG_OP <> 'INSERT' THEN
            v_rodada_antiga := OLD.rodada_numero;
        END IF;
        IF TG_OP <> 'DELETE' THEN
            v_rodada_nova := NEW.rodada_numero;
        END IF;
    ELSE
        IF TG_OP <> 'INSERT' THEN
            v_partida_antiga := OLD.partida_id;
        END IF;
        IF TG_OP <> 'DELETE' THEN
            v_partida_nova := NEW.partida_id;
        END IF;
        SELECT rodada_numero INTO v_rodada_antiga FROM partida
        WHERE id = v_partida_antiga;
        SELECT rodada_numero INTO v_rodada_nova FROM partida
        WHERE id = v_partida_nova;
    END IF;

    FOR v_estado IN
        SELECT estado FROM rodada
        WHERE numero IN (v_rodada_antiga, v_rodada_nova)
        ORDER BY numero
        FOR SHARE
    LOOP
        IF v_estado = 'consolidada' THEN
            RAISE EXCEPTION 'Não é permitido alterar dados de uma rodada consolidada.';
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

CREATE OR REPLACE TRIGGER trg_protege_scouts
BEFORE INSERT OR UPDATE OR DELETE ON atleta_partida_scout
FOR EACH ROW EXECUTE FUNCTION tg_protege_scouts_consolidados_func();

CREATE OR REPLACE TRIGGER trg_protege_atleta_partida
BEFORE INSERT OR UPDATE OR DELETE ON atleta_partida
FOR EACH ROW EXECUTE FUNCTION tg_protege_scouts_consolidados_func();

CREATE OR REPLACE TRIGGER trg_protege_partida
BEFORE INSERT OR UPDATE OR DELETE ON partida
FOR EACH ROW EXECUTE FUNCTION tg_protege_scouts_consolidados_func();

CREATE OR REPLACE TRIGGER trg_protege_clube_rodada
BEFORE INSERT OR UPDATE OR DELETE ON atleta_clube_rodada
FOR EACH ROW EXECUTE FUNCTION tg_protege_scouts_consolidados_func();

-- (e) Valida também alterações diretas na escalação.
CREATE OR REPLACE FUNCTION tg_valida_escalacao_func()
RETURNS TRIGGER AS $$
DECLARE
    v_numero INT;
    v_estado_rodada VARCHAR;
    v_esquema esquema_tatico%ROWTYPE;
    v_qtd RECORD;
    v_patrimonio NUMERIC;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_numero := OLD.rodada_numero;
    ELSE
        v_numero := NEW.rodada_numero;
    END IF;

    SELECT estado INTO v_estado_rodada FROM rodada WHERE numero = v_numero FOR SHARE;
    IF v_estado_rodada IS DISTINCT FROM 'aberta' THEN
        RAISE EXCEPTION 'A rodada não está aberta para alterações de escalação.';
    END IF;
    IF TG_OP <> 'INSERT' AND OLD.estado = 'confirmada' THEN
        RAISE EXCEPTION 'Uma escalação confirmada não pode ser alterada.';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE'
       AND (OLD.tecnico_id <> NEW.tecnico_id OR OLD.rodada_numero <> NEW.rodada_numero) THEN
        RAISE EXCEPTION 'Não é permitido trocar o técnico ou a rodada da escalação.';
    END IF;
    IF TG_OP = 'INSERT' AND NEW.estado IS DISTINCT FROM 'em_edicao' THEN
        RAISE EXCEPTION 'Uma nova escalação deve começar em edição.';
    END IF;

    IF NEW.estado = 'confirmada' THEN
        SELECT * INTO v_esquema FROM esquema_tatico WHERE nome = NEW.esquema_tatico_nome;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Esquema tático não encontrado.';
        END IF;

        SELECT COUNT(*) FILTER (WHERE a.posicao = 'gol') AS gol,
               COUNT(*) FILTER (WHERE a.posicao = 'lat') AS lat,
               COUNT(*) FILTER (WHERE a.posicao = 'zag') AS zag,
               COUNT(*) FILTER (WHERE a.posicao = 'mei') AS mei,
               COUNT(*) FILTER (WHERE a.posicao = 'ata') AS ata,
               COUNT(*) FILTER (WHERE a.posicao = 'tec') AS tec,
               COUNT(*) FILTER (WHERE ea.is_capitao AND a.posicao <> 'tec') AS capitaes,
               COALESCE(SUM(ea.preco_pago), 0) AS custo
        INTO v_qtd
        FROM escalacao_atleta ea
        JOIN atleta a ON a.id = ea.atleta_id
        WHERE ea.tecnico_id = NEW.tecnico_id AND ea.rodada_numero = NEW.rodada_numero;

        IF v_qtd.gol <> v_esquema.qtd_goleiro OR v_qtd.lat <> v_esquema.qtd_lateral
           OR v_qtd.zag <> v_esquema.qtd_zagueiro OR v_qtd.mei <> v_esquema.qtd_meia
           OR v_qtd.ata <> v_esquema.qtd_atacante OR v_qtd.tec <> v_esquema.qtd_tecnico THEN
            RAISE EXCEPTION 'A quantidade por posição não confere com o esquema tático.';
        END IF;
        IF v_qtd.capitaes <> 1 THEN
            RAISE EXCEPTION 'Escolha exatamente um capitão entre os 11 jogadores.';
        END IF;

        SELECT patrimonio_atual INTO v_patrimonio FROM tecnico WHERE id = NEW.tecnico_id;
        IF v_qtd.custo > v_patrimonio THEN
            RAISE EXCEPTION 'O preço total da escalação excede o patrimônio do técnico.';
        END IF;
        NEW.data_confirmacao := CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

CREATE OR REPLACE TRIGGER trg_valida_escalacao
BEFORE INSERT OR UPDATE OR DELETE ON escalacao
FOR EACH ROW EXECUTE FUNCTION tg_valida_escalacao_func();

CREATE OR REPLACE PROCEDURE prc_confirma_escalacao(p_tecnico_id INT, p_rodada_num INT)
AS $$
BEGIN
    -- A transição para confirmada passa pelas validações do gatilho.
    PERFORM 1 FROM rodada WHERE numero = p_rodada_num FOR SHARE;

    UPDATE escalacao SET estado = 'confirmada'
    WHERE tecnico_id = p_tecnico_id AND rodada_numero = p_rodada_num;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Escalação não encontrada para o técnico e rodada informados.';
    END IF;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

-- (f) A trava na liga serializa as inscrições que passam pelo procedimento.
CREATE OR REPLACE PROCEDURE prc_entrar_liga(p_tecnico_id INT, p_liga_id INT, p_codigo_convite VARCHAR)
AS $$
DECLARE
    v_tipo VARCHAR;
    v_convite VARCHAR;
    v_limite INT;
    v_total INT;
BEGIN
    SELECT tipo, codigo_convite, limite_participantes INTO v_tipo, v_convite, v_limite
    FROM liga WHERE id = p_liga_id FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Liga não encontrada.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tecnico WHERE id = p_tecnico_id) THEN
        RAISE EXCEPTION 'Técnico não encontrado.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM participacao_liga WHERE tecnico_id = p_tecnico_id AND liga_id = p_liga_id
    ) THEN
        RAISE EXCEPTION 'O técnico já participa desta liga.';
    END IF;
    IF v_tipo = 'privada' AND v_convite IS DISTINCT FROM p_codigo_convite THEN
        RAISE EXCEPTION 'Código de convite inválido para esta liga privada.';
    END IF;

    SELECT COUNT(*) INTO v_total FROM participacao_liga WHERE liga_id = p_liga_id;
    IF v_total >= v_limite THEN
        RAISE EXCEPTION 'A liga atingiu o limite máximo de participantes.';
    END IF;

    INSERT INTO participacao_liga (tecnico_id, liga_id)
    VALUES (p_tecnico_id, p_liga_id);
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

-- (g) O preço de escalação e o preço calculado após a rodada têm usos distintos.
ALTER TABLE historico_preco
    ADD COLUMN IF NOT EXISTS preco_apos_rodada NUMERIC(6,2)
    CHECK (preco_apos_rodada >= 1.00);

CREATE OR REPLACE PROCEDURE prc_consolidar_rodada(p_rodada_num INT)
AS $$
DECLARE
    v_estado VARCHAR;
BEGIN
    SELECT estado INTO v_estado
    FROM rodada
    WHERE numero = p_rodada_num
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rodada não encontrada.';
    END IF;

    IF v_estado <> 'fechada' THEN
        RAISE EXCEPTION 'A rodada precisa estar fechada e ainda não consolidada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM partida
        WHERE rodada_numero = p_rodada_num AND valida AND placar_mandante IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'A rodada não tem partidas válidas com placar.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM partida
        WHERE rodada_numero = p_rodada_num
          AND valida
          AND (placar_mandante IS NULL OR placar_visitante IS NULL)
    ) THEN
        RAISE EXCEPTION 'Há partidas válidas ainda sem placar nesta rodada.';
    END IF;

    -- Utiliza o último preço conhecido se ainda não houver preço nesta rodada.
    INSERT INTO historico_preco (atleta_id, rodada_numero, preco)
    SELECT DISTINCT ON (hp.atleta_id)
           hp.atleta_id,
           p_rodada_num,
           COALESCE(hp.preco_apos_rodada, hp.preco)
    FROM historico_preco hp
    WHERE hp.rodada_numero < p_rodada_num
    ORDER BY hp.atleta_id, hp.rodada_numero DESC
    ON CONFLICT (atleta_id, rodada_numero) DO NOTHING;

    -- Calcula a variação de preço e preserva o preço usado na escalação.
    --Greatest: Maior valor e Least: Menor valor. Limita a variação de preço entre -1,50 e +1,50.
    --Greatest(1.00, ...) garante que o preço mínimo seja 1,00.
    UPDATE historico_preco hp
    SET preco_apos_rodada = GREATEST(
        1.00,
        hp.preco + GREATEST(-1.50, LEAST(1.50, v.variacao))
    )
    FROM (
        SELECT base.atleta_id,
               COALESCE(
                   ROUND(0.10 * (r.pontos_rodada - r.media_anterior), 2),
                   0
               ) AS variacao
        FROM historico_preco base
        LEFT JOIN (
            SELECT pontos.atleta_id,
                   MAX(pontos.valor) FILTER (
                       WHERE pontos.rodada_numero = p_rodada_num
                   ) AS pontos_rodada,
                   AVG(pontos.valor) FILTER (
                       WHERE pontos.rodada_numero < p_rodada_num
                   ) AS media_anterior
            FROM (
                SELECT rp.atleta_id,
                       rp.rodada_numero,
                       f_pontos_atleta(rp.atleta_id, rp.rodada_numero) AS valor
                FROM (
                    SELECT DISTINCT ap.atleta_id, p.rodada_numero
                    FROM atleta_partida ap
                    JOIN partida p ON p.id = ap.partida_id
                    JOIN atleta a ON a.id = ap.atleta_id
                    JOIN rodada r ON r.numero = p.rodada_numero
                    WHERE a.posicao <> 'tec'
                      AND ap.entrou_em_campo
                      AND p.valida
                      AND (
                          r.numero = p_rodada_num
                          OR (r.numero < p_rodada_num AND r.estado = 'consolidada')
                      )
                ) AS rp
                UNION ALL
                SELECT acr.atleta_id,
                       acr.rodada_numero,
                       f_pontos_tecnico_real(acr.atleta_id, acr.rodada_numero)
                FROM atleta_clube_rodada acr
                JOIN atleta a ON a.id = acr.atleta_id
                JOIN rodada r ON r.numero = acr.rodada_numero
                WHERE a.posicao = 'tec'
                  AND (
                      r.numero = p_rodada_num
                      OR (r.numero < p_rodada_num AND r.estado = 'consolidada')
                  )
            ) AS pontos
            GROUP BY pontos.atleta_id
        ) AS r ON r.atleta_id = base.atleta_id
        WHERE base.rodada_numero = p_rodada_num
    ) AS v
    WHERE hp.atleta_id = v.atleta_id
      AND hp.rodada_numero = p_rodada_num;

    -- Impede a consolidação se faltar o novo preço de um atleta escalado.
    IF EXISTS (
        SELECT 1
        FROM escalacao_atleta ea
        JOIN escalacao e ON e.tecnico_id = ea.tecnico_id AND e.rodada_numero = ea.rodada_numero
        LEFT JOIN historico_preco hp ON hp.atleta_id = ea.atleta_id AND hp.rodada_numero = ea.rodada_numero
        WHERE ea.rodada_numero = p_rodada_num AND e.estado = 'confirmada' AND hp.preco_apos_rodada IS NULL
    ) THEN
        RAISE EXCEPTION 'Falta preço calculado para um atleta de escalação confirmada.';
    END IF;

    -- Soma a diferença entre o preço novo e o preço pago por técnico.
    UPDATE tecnico t
    SET patrimonio_atual = t.patrimonio_atual + s.variacao
    FROM (
        SELECT ea.tecnico_id,
               SUM(hp.preco_apos_rodada - ea.preco_pago) AS variacao
        FROM escalacao_atleta ea
        JOIN escalacao e ON e.tecnico_id = ea.tecnico_id AND e.rodada_numero = ea.rodada_numero
        JOIN historico_preco hp ON hp.atleta_id = ea.atleta_id AND hp.rodada_numero = ea.rodada_numero
        WHERE ea.rodada_numero = p_rodada_num AND e.estado = 'confirmada'
        GROUP BY ea.tecnico_id
    ) AS s
    WHERE t.id = s.tecnico_id;

    -- Registra o saldo de todos, inclusive de quem não escalou.
    INSERT INTO patrimonio_rodada (tecnico_id, rodada_numero, patrimonio)
    SELECT id, p_rodada_num, patrimonio_atual
    FROM tecnico
    ON CONFLICT (tecnico_id, rodada_numero)
    DO UPDATE SET patrimonio = EXCLUDED.patrimonio;

    UPDATE rodada
    SET estado = 'consolidada'
    WHERE numero = p_rodada_num;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

-- abrir rodada.
CREATE OR REPLACE PROCEDURE prc_abrir_rodada(p_rodada_num INT)
AS $$
BEGIN
    IF p_rodada_num IS NULL OR p_rodada_num NOT BETWEEN 1 AND 38 THEN
        RAISE EXCEPTION 'Informe uma rodada entre 1 e 38.';
    END IF;
    IF EXISTS (SELECT 1 FROM rodada WHERE estado = 'aberta') THEN
        RAISE EXCEPTION 'Já existe uma rodada aberta.';
    END IF;

    INSERT INTO rodada (numero, estado) VALUES (p_rodada_num, 'aberta')
    ON CONFLICT (numero) DO NOTHING;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'A rodada já existe e não pode ser reaberta.';
    END IF;

    INSERT INTO historico_preco (atleta_id, rodada_numero, preco)
    SELECT DISTINCT ON (hp.atleta_id) hp.atleta_id, p_rodada_num,
           COALESCE(hp.preco_apos_rodada, hp.preco)
    FROM historico_preco hp
    WHERE hp.rodada_numero < p_rodada_num
    ORDER BY hp.atleta_id, hp.rodada_numero DESC
    ON CONFLICT (atleta_id, rodada_numero) DO NOTHING;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Já existe uma rodada aberta.';
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

-- fechar rodada.
CREATE OR REPLACE PROCEDURE prc_fechar_rodada(p_rodada_num INT)
AS $$
BEGIN
    UPDATE rodada SET estado = 'fechada'
    WHERE numero = p_rodada_num AND estado = 'aberta';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Somente uma rodada aberta pode ser fechada.';
    END IF;
END;
$$ LANGUAGE plpgsql SET search_path TO liga_facom, pg_temp;

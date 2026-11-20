SET search_path TO liga_facom;

CREATE OR REPLACE FUNCTION f_pontos_atleta(p_atleta_id INT, p_rodada_num INT)
RETURNS NUMERIC LANGUAGE plpgsql STABLE AS $$
DECLARE v_pos VARCHAR(3); v_entrou BOOLEAN; v_pontos NUMERIC; v_clube INT; v_mandante INT; v_visitante INT; v_pm INT; v_pv INT;
BEGIN
  SELECT posicao INTO v_pos FROM atleta WHERE id=p_atleta_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Atleta % não encontrado.', p_atleta_id; END IF;
  IF v_pos='tec' THEN
    SELECT clube_id INTO v_clube FROM atleta_clube_rodada WHERE atleta_id=p_atleta_id AND rodada_numero=p_rodada_num;
    IF v_clube IS NULL THEN RETURN 0; END IF;
    SELECT mandante_id,visitante_id,placar_mandante,placar_visitante INTO v_mandante,v_visitante,v_pm,v_pv FROM partida WHERE rodada_numero=p_rodada_num AND valida=true AND (mandante_id=v_clube OR visitante_id=v_clube) ORDER BY id LIMIT 1;
    IF NOT FOUND OR v_pm IS NULL OR v_pv IS NULL THEN RETURN 0; END IF;
    IF (v_clube=v_mandante AND v_pm>v_pv) OR (v_clube=v_visitante AND v_pv>v_pm) THEN RETURN 5; END IF;
    IF v_pm=v_pv THEN RETURN 2; END IF;
    RETURN 0;
  END IF;
  SELECT COALESCE(bool_or(ap.entrou_em_campo),false) INTO v_entrou
  FROM atleta_partida ap JOIN partida p ON p.id=ap.partida_id
  WHERE ap.atleta_id=p_atleta_id AND p.rodada_numero=p_rodada_num;
  IF NOT v_entrou THEN RETURN 0; END IF;
  SELECT COALESCE(SUM(aps.quantidade*ts.valor_pontos),0) INTO v_pontos
  FROM atleta_partida_scout aps
  JOIN tipo_scout ts ON ts.sigla=aps.sigla_scout
  JOIN atleta_partida ap ON ap.atleta_id=aps.atleta_id AND ap.partida_id=aps.partida_id
  JOIN partida p ON p.id=ap.partida_id
  JOIN tipo_scout_posicao tsp ON tsp.sigla_scout=ts.sigla AND tsp.posicao=v_pos
  WHERE ap.atleta_id=p_atleta_id AND p.rodada_numero=p_rodada_num;
  RETURN COALESCE(v_pontos,0);
END $$;




CREATE OR REPLACE FUNCTION f_pontos_escalacao(p_tecnico_id INT, p_rodada_num INT)
RETURNS NUMERIC LANGUAGE plpgsql STABLE AS $$
DECLARE v_total NUMERIC:=0; v_tecnico_id_atleta INT; v_clube INT; v_mandante INT; v_visitante INT; v_pm INT; v_pv INT; v_pos NUMERIC;
BEGIN
 SELECT COALESCE(SUM(f_pontos_atleta(ea.atleta_id,p_rodada_num) * CASE WHEN ea.is_capitao THEN 1.5 ELSE 1 END),0)
 INTO v_total FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id
 WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao <> 'tec';
 SELECT ea.atleta_id, acr.clube_id INTO v_tecnico_id_atleta,v_clube
 FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id
 LEFT JOIN atleta_clube_rodada acr ON acr.atleta_id=ea.atleta_id AND acr.rodada_numero=ea.rodada_numero
 WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao='tec';
 IF v_tecnico_id_atleta IS NOT NULL AND v_clube IS NOT NULL THEN
   SELECT mandante_id,visitante_id,placar_mandante,placar_visitante INTO v_mandante,v_visitante,v_pm,v_pv
   FROM partida WHERE rodada_numero=p_rodada_num AND valida=true AND (mandante_id=v_clube OR visitante_id=v_clube)
   ORDER BY id LIMIT 1;
   IF FOUND AND v_pm IS NOT NULL AND v_pv IS NOT NULL THEN
     IF (v_clube=v_mandante AND v_pm>v_pv) OR (v_clube=v_visitante AND v_pv>v_pm) THEN v_total:=v_total+5;
     ELSIF v_pm=v_pv THEN v_total:=v_total+2; END IF;
   END IF;
 END IF;
 RETURN v_total;
END $$;

CREATE OR REPLACE FUNCTION tg_valida_escalacao_func() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_estado VARCHAR;
BEGIN
 SELECT estado INTO v_estado FROM rodada WHERE numero=NEW.rodada_numero;
 IF NOT FOUND THEN RAISE EXCEPTION 'Rodada % não existe.',NEW.rodada_numero; END IF;
 IF v_estado <> 'aberta' THEN RAISE EXCEPTION 'A rodada não está aberta para escalações.'; END IF;
 IF TG_OP='UPDATE' AND (OLD.estado='confirmada' OR OLD.tecnico_id<>NEW.tecnico_id OR OLD.rodada_numero<>NEW.rodada_numero) THEN
   RAISE EXCEPTION 'Escalação confirmada não pode ser alterada.';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_valida_escalacao BEFORE INSERT OR UPDATE ON escalacao FOR EACH ROW EXECUTE FUNCTION tg_valida_escalacao_func();
CREATE OR REPLACE FUNCTION tg_bloqueia_delete_escalacao() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_estado VARCHAR;
BEGIN SELECT estado INTO v_estado FROM rodada WHERE numero=OLD.rodada_numero;
 IF v_estado IS DISTINCT FROM 'aberta' OR OLD.estado='confirmada' THEN RAISE EXCEPTION 'Não é permitido remover escalação fora de edição em rodada aberta.'; END IF;
 RETURN OLD; END $$;
CREATE TRIGGER trg_bloqueia_delete_escalacao BEFORE DELETE ON escalacao FOR EACH ROW EXECUTE FUNCTION tg_bloqueia_delete_escalacao();





CREATE OR REPLACE FUNCTION tg_valida_escalacao_atleta_func() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_tecnico INT; v_rodada INT; v_atleta INT; v_estado VARCHAR; v_situacao VARCHAR; v_pos VARCHAR(3); v_esquema VARCHAR(10); v_patrimonio NUMERIC; v_total NUMERIC; v_preco NUMERIC; v_atleta_excluir INT;
BEGIN
 v_tecnico:=CASE WHEN TG_OP='DELETE' THEN OLD.tecnico_id ELSE NEW.tecnico_id END;
 v_rodada:=CASE WHEN TG_OP='DELETE' THEN OLD.rodada_numero ELSE NEW.rodada_numero END;
 v_atleta:=CASE WHEN TG_OP='DELETE' THEN OLD.atleta_id ELSE NEW.atleta_id END;
 v_atleta_excluir:=NULL; IF TG_OP='UPDATE' THEN v_atleta_excluir:=OLD.atleta_id; END IF;
 SELECT estado INTO v_estado FROM rodada WHERE numero=v_rodada;
 IF v_estado IS DISTINCT FROM 'aberta' THEN RAISE EXCEPTION 'A rodada não está aberta para alterações.'; END IF;
 IF EXISTS(SELECT 1 FROM escalacao WHERE tecnico_id=v_tecnico AND rodada_numero=v_rodada AND estado='confirmada') THEN RAISE EXCEPTION 'Escalação confirmada não pode ser alterada.'; END IF;
 IF TG_OP<>'DELETE' THEN
   SELECT situacao_atual,posicao INTO v_situacao,v_pos FROM atleta WHERE id=v_atleta;
   IF NOT FOUND THEN RAISE EXCEPTION 'Atleta não encontrado.'; END IF;
   IF v_situacao NOT IN ('provavel','duvida') THEN RAISE EXCEPTION 'Só é permitido escalar atleta provável ou em dúvida.'; END IF;
   SELECT patrimonio_atual INTO v_patrimonio FROM tecnico WHERE id=v_tecnico;
   SELECT COALESCE(SUM(preco_pago),0) INTO v_total FROM escalacao_atleta
    WHERE tecnico_id=v_tecnico AND rodada_numero=v_rodada AND (v_atleta_excluir IS NULL OR atleta_id<>v_atleta_excluir);
   v_total:=v_total+NEW.preco_pago;
   IF v_total>v_patrimonio THEN RAISE EXCEPTION 'O custo da escalação excede o patrimônio disponível.'; END IF;
   SELECT esquema_tatico_nome INTO v_esquema FROM escalacao WHERE tecnico_id=v_tecnico AND rodada_numero=v_rodada;
   IF v_esquema IS NOT NULL AND EXISTS(
      SELECT 1 FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id
      JOIN esquema_tatico et ON et.nome=v_esquema
      WHERE ea.tecnico_id=v_tecnico AND ea.rodada_numero=v_rodada AND a.posicao=v_pos
      GROUP BY a.posicao
      HAVING COUNT(*) >= CASE v_pos WHEN 'gol' THEN et.qtd_goleiro WHEN 'lat' THEN et.qtd_lateral WHEN 'zag' THEN et.qtd_zagueiro WHEN 'mei' THEN et.qtd_meia WHEN 'ata' THEN et.qtd_atacante WHEN 'tec' THEN et.qtd_tecnico END
   ) AND NOT (TG_OP='UPDATE' AND v_atleta_excluir=NEW.atleta_id) THEN RAISE EXCEPTION 'Quantidade máxima dessa posição já atingida no esquema.'; END IF;
   SELECT preco INTO v_preco FROM historico_preco WHERE atleta_id=v_atleta AND rodada_numero=v_rodada;
   IF NOT FOUND THEN RAISE EXCEPTION 'Não há preço cadastrado para o atleta % na rodada %.',v_atleta,v_rodada; END IF;
   IF v_preco<>NEW.preco_pago THEN RAISE EXCEPTION 'O preço pago deve ser igual ao preço do atleta nesta rodada.'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
CREATE TRIGGER trg_valida_escalacao_atleta BEFORE INSERT OR UPDATE OR DELETE ON escalacao_atleta FOR EACH ROW EXECUTE FUNCTION tg_valida_escalacao_atleta_func();






CREATE OR REPLACE FUNCTION tg_protege_dados_rodada_func() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_partida INT; v_rodada INT; v_estado VARCHAR;
BEGIN
 v_partida:=CASE WHEN TG_OP='DELETE' THEN OLD.partida_id ELSE NEW.partida_id END;
 SELECT rodada_numero INTO v_rodada FROM partida WHERE id=v_partida;
 SELECT estado INTO v_estado FROM rodada WHERE numero=v_rodada;
 IF v_estado='consolidada' THEN RAISE EXCEPTION 'Não é permitido alterar dados de rodada consolidada.'; END IF;
 IF TG_OP='UPDATE' THEN
   SELECT p.rodada_numero INTO v_rodada FROM partida p WHERE p.id=OLD.partida_id;
   SELECT estado INTO v_estado FROM rodada WHERE numero=v_rodada;
   IF v_estado='consolidada' THEN RAISE EXCEPTION 'Não é permitido mover dados para fora de rodada consolidada.'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
CREATE TRIGGER trg_protege_scouts BEFORE INSERT OR UPDATE OR DELETE ON atleta_partida_scout FOR EACH ROW EXECUTE FUNCTION tg_protege_dados_rodada_func();
CREATE TRIGGER trg_protege_atleta_partida BEFORE INSERT OR UPDATE OR DELETE ON atleta_partida FOR EACH ROW EXECUTE FUNCTION tg_protege_dados_rodada_func();
CREATE OR REPLACE FUNCTION tg_protege_partida_func() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_estado VARCHAR;
BEGIN SELECT estado INTO v_estado FROM rodada WHERE numero=CASE WHEN TG_OP='DELETE' THEN OLD.rodada_numero ELSE NEW.rodada_numero END;
 IF v_estado='consolidada' THEN RAISE EXCEPTION 'Não é permitido alterar partida de rodada consolidada.'; END IF;
 IF TG_OP='UPDATE' THEN SELECT estado INTO v_estado FROM rodada WHERE numero=OLD.rodada_numero; IF v_estado='consolidada' THEN RAISE EXCEPTION 'Não é permitido mover partida de rodada consolidada.'; END IF; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END $$;
CREATE TRIGGER trg_protege_partida BEFORE INSERT OR UPDATE OR DELETE ON partida FOR EACH ROW EXECUTE FUNCTION tg_protege_partida_func();





CREATE OR REPLACE PROCEDURE prc_confirma_escalacao(p_tecnico_id INT,p_rodada_num INT) LANGUAGE plpgsql AS $$
DECLARE v_esquema VARCHAR(10); v_estado VARCHAR; v_capitaes INT; v_total INT; v_preco NUMERIC; v_patrimonio NUMERIC; v_qtd RECORD; v_cont INT;
BEGIN
 SELECT r.estado,e.esquema_tatico_nome INTO v_estado,v_esquema FROM escalacao e JOIN rodada r ON r.numero=e.rodada_numero WHERE e.tecnico_id=p_tecnico_id AND e.rodada_numero=p_rodada_num;
 IF NOT FOUND THEN RAISE EXCEPTION 'Escalação ou rodada não encontrada.'; END IF;
 IF v_estado<>'aberta' THEN RAISE EXCEPTION 'Só é possível confirmar escalação em rodada aberta.'; END IF;
 IF EXISTS(SELECT 1 FROM escalacao WHERE tecnico_id=p_tecnico_id AND rodada_numero=p_rodada_num AND estado='confirmada') THEN RAISE EXCEPTION 'Escalação já confirmada.'; END IF;
 SELECT * INTO v_qtd FROM esquema_tatico WHERE nome=v_esquema;
 SELECT COUNT(*),COUNT(*) FILTER(WHERE ea.is_capitao),COALESCE(SUM(ea.preco_pago),0) INTO v_total,v_capitaes,v_preco
 FROM escalacao_atleta ea WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num;
 IF v_total<>12 THEN RAISE EXCEPTION 'A escalação deve conter exatamente 12 itens: 11 atletas e 1 técnico real.'; END IF;
 IF v_capitaes<>1 THEN RAISE EXCEPTION 'Escolha exatamente um capitão.'; END IF;
 IF EXISTS(SELECT 1 FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND ea.is_capitao AND a.posicao='tec') THEN RAISE EXCEPTION 'O técnico real não pode ser capitão.'; END IF;
 SELECT COUNT(*) INTO v_cont FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao='gol'; IF v_cont<>v_qtd.qtd_goleiro THEN RAISE EXCEPTION 'Quantidade de goleiros incompatível com o esquema.'; END IF;
 SELECT COUNT(*) INTO v_cont FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao='lat'; IF v_cont<>v_qtd.qtd_lateral THEN RAISE EXCEPTION 'Quantidade de laterais incompatível com o esquema.'; END IF;
 SELECT COUNT(*) INTO v_cont FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao='zag'; IF v_cont<>v_qtd.qtd_zagueiro THEN RAISE EXCEPTION 'Quantidade de zagueiros incompatível com o esquema.'; END IF;
 SELECT COUNT(*) INTO v_cont FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao='mei'; IF v_cont<>v_qtd.qtd_meia THEN RAISE EXCEPTION 'Quantidade de meias incompatível com o esquema.'; END IF;
 SELECT COUNT(*) INTO v_cont FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao='ata'; IF v_cont<>v_qtd.qtd_atacante THEN RAISE EXCEPTION 'Quantidade de atacantes incompatível com o esquema.'; END IF;
 SELECT COUNT(*) INTO v_cont FROM escalacao_atleta ea JOIN atleta a ON a.id=ea.atleta_id WHERE ea.tecnico_id=p_tecnico_id AND ea.rodada_numero=p_rodada_num AND a.posicao='tec'; IF v_cont<>1 THEN RAISE EXCEPTION 'A escalação deve conter exatamente um técnico real.'; END IF;
 SELECT patrimonio_atual INTO v_patrimonio FROM tecnico WHERE id=p_tecnico_id;
 IF v_preco>v_patrimonio THEN RAISE EXCEPTION 'O preço total excede o patrimônio.'; END IF;
 UPDATE escalacao SET estado='confirmada',data_confirmacao=CURRENT_TIMESTAMP WHERE tecnico_id=p_tecnico_id AND rodada_numero=p_rodada_num;
END $$;





CREATE OR REPLACE PROCEDURE prc_entrar_liga(p_tecnico_id INT,p_liga_id INT,p_codigo_convite VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_tipo VARCHAR; v_codigo VARCHAR; v_limite INT; v_total INT;
BEGIN
 SELECT tipo,codigo_convite,limite_participantes INTO v_tipo,v_codigo,v_limite FROM liga WHERE id=p_liga_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Liga não encontrada.'; END IF;
 IF EXISTS(SELECT 1 FROM participacao_liga WHERE tecnico_id=p_tecnico_id AND liga_id=p_liga_id) THEN RAISE EXCEPTION 'O técnico já participa desta liga.'; END IF;
 IF v_tipo='privada' AND (p_codigo_convite IS NULL OR p_codigo_convite IS DISTINCT FROM v_codigo) THEN RAISE EXCEPTION 'Código de convite inválido para esta liga privada.'; END IF;
 SELECT COUNT(*) INTO v_total FROM participacao_liga WHERE liga_id=p_liga_id;
 IF v_total>=v_limite THEN RAISE EXCEPTION 'A liga atingiu o limite máximo de participantes.'; END IF;
 INSERT INTO participacao_liga(tecnico_id,liga_id,data_entrada) VALUES(p_tecnico_id,p_liga_id,CURRENT_DATE);
END $$;




CREATE OR REPLACE FUNCTION tg_dono_participa_liga_func() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN INSERT INTO participacao_liga(tecnico_id,liga_id,data_entrada) VALUES(NEW.dono_id,NEW.id,CURRENT_DATE) ON CONFLICT DO NOTHING; RETURN NEW; END $$;
CREATE TRIGGER trg_dono_participa_liga AFTER INSERT ON liga FOR EACH ROW EXECUTE FUNCTION tg_dono_participa_liga_func();






CREATE OR REPLACE FUNCTION tg_transicao_rodada_func() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.estado=NEW.estado THEN RETURN NEW; END IF;
 IF NOT ((OLD.estado='fechada' AND NEW.estado='consolidada') OR (OLD.estado='aberta' AND NEW.estado='fechada') OR (OLD.estado='fechada' AND NEW.estado='aberta' AND NOT EXISTS(SELECT 1 FROM partida WHERE rodada_numero=OLD.numero))) THEN
   RAISE EXCEPTION 'Transição inválida de rodada: % -> %.',OLD.estado,NEW.estado;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_transicao_rodada BEFORE UPDATE OF estado ON rodada FOR EACH ROW EXECUTE FUNCTION tg_transicao_rodada_func();
CREATE OR REPLACE PROCEDURE prc_abrir_rodada(p_num INT) LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM rodada WHERE estado='aberta') THEN RAISE EXCEPTION 'Já existe uma rodada aberta.'; END IF;
 IF EXISTS(SELECT 1 FROM rodada WHERE numero=p_num) THEN
   UPDATE rodada SET estado='aberta' WHERE numero=p_num AND estado='fechada';
   IF NOT FOUND THEN RAISE EXCEPTION 'A rodada existente não está apta a ser aberta.'; END IF;
 ELSE INSERT INTO rodada(numero,estado) VALUES(p_num,'aberta'); END IF;
END $$;
CREATE OR REPLACE PROCEDURE prc_fechar_rodada(p_num INT) LANGUAGE plpgsql AS $$
BEGIN UPDATE rodada SET estado='fechada' WHERE numero=p_num AND estado='aberta'; IF NOT FOUND THEN RAISE EXCEPTION 'Somente rodada aberta pode ser fechada.'; END IF; END $$;






CREATE OR REPLACE PROCEDURE prc_consolidar_rodada(p_rodada_num INT) LANGUAGE plpgsql AS $$
DECLARE v_estado VARCHAR; r RECORD; v_pts NUMERIC; v_media NUMERIC; v_var NUMERIC; v_preco_ant NUMERIC; v_preco_novo NUMERIC; v_delta NUMERIC; r2 RECORD;
BEGIN
 SELECT estado INTO v_estado FROM rodada WHERE numero=p_rodada_num FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Rodada não encontrada.'; END IF;
 IF v_estado<>'fechada' THEN RAISE EXCEPTION 'A rodada precisa estar fechada e ainda não consolidada.'; END IF;
 FOR r IN SELECT DISTINCT candidatos.atleta_id,candidatos.posicao FROM (
   SELECT ap.atleta_id,a.posicao FROM atleta_partida ap JOIN partida p ON p.id=ap.partida_id JOIN atleta a ON a.id=ap.atleta_id WHERE p.rodada_numero=p_rodada_num AND ap.entrou_em_campo=true
   UNION ALL
   SELECT acr.atleta_id,a.posicao FROM atleta_clube_rodada acr JOIN atleta a ON a.id=acr.atleta_id JOIN partida p ON p.rodada_numero=acr.rodada_numero AND p.valida AND (p.mandante_id=acr.clube_id OR p.visitante_id=acr.clube_id) WHERE acr.rodada_numero=p_rodada_num AND a.posicao='tec' AND p.placar_mandante IS NOT NULL
 ) candidatos LOOP
   SELECT preco INTO v_preco_ant FROM historico_preco WHERE atleta_id=r.atleta_id AND rodada_numero=p_rodada_num;
   IF v_preco_ant IS NULL THEN SELECT preco INTO v_preco_ant FROM historico_preco WHERE atleta_id=r.atleta_id AND rodada_numero<p_rodada_num ORDER BY rodada_numero DESC LIMIT 1; END IF;
   IF v_preco_ant IS NULL THEN CONTINUE; END IF;
   SELECT COALESCE(AVG(f_pontos_atleta(r.atleta_id,pr.numero)),0) INTO v_media FROM rodada pr WHERE pr.estado='consolidada' AND pr.numero<p_rodada_num AND (
     (r.posicao='tec' AND EXISTS(SELECT 1 FROM atleta_clube_rodada acr2 JOIN partida p2 ON p2.rodada_numero=acr2.rodada_numero AND p2.valida AND (p2.mandante_id=acr2.clube_id OR p2.visitante_id=acr2.clube_id) WHERE acr2.atleta_id=r.atleta_id AND acr2.rodada_numero=pr.numero AND p2.placar_mandante IS NOT NULL))
     OR (r.posicao<>'tec' AND EXISTS(SELECT 1 FROM atleta_partida ap2 JOIN partida p2 ON p2.id=ap2.partida_id WHERE ap2.atleta_id=r.atleta_id AND ap2.entrou_em_campo=true AND p2.rodada_numero=pr.numero))
   );
   v_pts:=CASE WHEN r.posicao='tec' THEN (
      SELECT CASE WHEN (CASE WHEN p.mandante_id=acr.clube_id THEN p.placar_mandante ELSE p.placar_visitante END)>(CASE WHEN p.mandante_id=acr.clube_id THEN p.placar_visitante ELSE p.placar_mandante END) THEN 5 WHEN p.placar_mandante=p.placar_visitante THEN 2 ELSE 0 END
      FROM atleta_clube_rodada acr JOIN partida p ON p.rodada_numero=p_rodada_num AND p.valida AND (p.mandante_id=acr.clube_id OR p.visitante_id=acr.clube_id) WHERE acr.atleta_id=r.atleta_id AND acr.rodada_numero=p_rodada_num LIMIT 1
   ) ELSE f_pontos_atleta(r.atleta_id,p_rodada_num) END;
   v_var:=LEAST(1.50,GREATEST(-1.50,ROUND(0.10*(COALESCE(v_pts,0)-v_media),2)));
   v_preco_novo:=GREATEST(1.00,v_preco_ant+v_var);
   INSERT INTO historico_preco(atleta_id,rodada_numero,preco) VALUES(r.atleta_id,p_rodada_num,v_preco_novo)
   ON CONFLICT(atleta_id,rodada_numero) DO UPDATE SET preco=EXCLUDED.preco;
 END LOOP;
 INSERT INTO historico_preco(atleta_id,rodada_numero,preco)
 SELECT a.id,p_rodada_num,ult.preco FROM atleta a
 JOIN LATERAL (SELECT hp.preco FROM historico_preco hp WHERE hp.atleta_id=a.id AND hp.rodada_numero<p_rodada_num ORDER BY hp.rodada_numero DESC LIMIT 1) ult ON true
 WHERE NOT EXISTS(SELECT 1 FROM historico_preco atual WHERE atual.atleta_id=a.id AND atual.rodada_numero=p_rodada_num)
 ON CONFLICT(atleta_id,rodada_numero) DO NOTHING;
 FOR r IN SELECT e.tecnico_id,COALESCE(SUM(ea.preco_pago),0) AS custo FROM escalacao e LEFT JOIN escalacao_atleta ea ON ea.tecnico_id=e.tecnico_id AND ea.rodada_numero=e.rodada_numero WHERE e.rodada_numero=p_rodada_num AND e.estado='confirmada' GROUP BY e.tecnico_id LOOP
   v_delta:=0;
   FOR r2 IN SELECT ea.atleta_id,ea.preco_pago FROM escalacao_atleta ea WHERE ea.tecnico_id=r.tecnico_id AND ea.rodada_numero=p_rodada_num LOOP
     SELECT preco INTO v_preco_novo FROM historico_preco WHERE atleta_id=r2.atleta_id AND rodada_numero=p_rodada_num;
     IF v_preco_novo IS NULL THEN RAISE EXCEPTION 'Falta preço histórico do atleta % na rodada %.',r2.atleta_id,p_rodada_num; END IF;
     v_delta:=v_delta+(v_preco_novo-r2.preco_pago);
   END LOOP;
   UPDATE tecnico SET patrimonio_atual=patrimonio_atual+v_delta WHERE id=r.tecnico_id;
   INSERT INTO patrimonio_rodada(tecnico_id,rodada_numero,patrimonio) SELECT id,p_rodada_num,patrimonio_atual FROM tecnico WHERE id=r.tecnico_id ON CONFLICT(tecnico_id,rodada_numero) DO UPDATE SET patrimonio=EXCLUDED.patrimonio;
 END LOOP;
 INSERT INTO patrimonio_rodada(tecnico_id,rodada_numero,patrimonio) SELECT id,p_rodada_num,patrimonio_atual FROM tecnico ON CONFLICT(tecnico_id,rodada_numero) DO UPDATE SET patrimonio=EXCLUDED.patrimonio;
 UPDATE rodada SET estado='consolidada' WHERE numero=p_rodada_num;
EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Falha ao consolidar rodada %: %',p_rodada_num,SQLERRM;
END $$;

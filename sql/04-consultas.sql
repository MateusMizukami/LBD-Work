SET search_path TO liga_facom;

-- (a) Mercado da rodada aberta, com média e última pontuação consolidada.
-- Uma linha por atleta e rodada, ainda que ele tenha mais de uma partida.
CREATE OR REPLACE VIEW vw_pontos_jogador AS
SELECT ap.atleta_id,
       r.numero AS rodada_numero,
       f_pontos_atleta(ap.atleta_id, r.numero) AS pontos
FROM atleta_partida ap
JOIN atleta a ON a.id = ap.atleta_id
JOIN partida p ON p.id = ap.partida_id
JOIN rodada r ON r.numero = p.rodada_numero
WHERE a.posicao <> 'tec' AND ap.entrou_em_campo AND p.valida AND r.estado = 'consolidada'
GROUP BY ap.atleta_id, r.numero;

CREATE OR REPLACE VIEW vw_pontos_tecnico_real AS
SELECT acr.atleta_id,
       r.numero AS rodada_numero,
       f_pontos_tecnico_real(acr.atleta_id, r.numero) AS pontos
FROM atleta_clube_rodada acr
JOIN atleta a ON a.id = acr.atleta_id
JOIN rodada r ON r.numero = acr.rodada_numero
JOIN partida p ON p.rodada_numero = r.numero AND (acr.clube_id = p.mandante_id OR acr.clube_id = p.visitante_id)
WHERE a.posicao = 'tec' AND r.estado = 'consolidada' AND p.valida AND p.placar_mandante IS NOT NULL AND p.placar_visitante IS NOT NULL
GROUP BY acr.atleta_id, r.numero;

CREATE OR REPLACE VIEW vw_pontos_atleta AS
SELECT a.id AS atleta_id,
       a.apelido,
       a.posicao,
       r.numero AS rodada_numero,
       COALESCE(j.pontos, t.pontos) AS pontos
FROM atleta a
JOIN rodada r ON r.estado = 'consolidada'
LEFT JOIN vw_pontos_jogador j ON j.atleta_id = a.id AND j.rodada_numero = r.numero
LEFT JOIN vw_pontos_tecnico_real t ON t.atleta_id = a.id AND t.rodada_numero = r.numero
WHERE j.atleta_id IS NOT NULL OR t.atleta_id IS NOT NULL;

CREATE OR REPLACE VIEW vw_resumo_atleta AS
SELECT atleta_id,
       COUNT(*) AS qtd_rodadas,
       SUM(pontos) / COUNT(*) AS media,
       MAX(rodada_numero) AS ultima_rodada
FROM vw_pontos_atleta
GROUP BY atleta_id;

CREATE OR REPLACE VIEW vw_mercado AS
SELECT a.id AS atleta_id,
       a.apelido,
       c.nome AS clube,
       a.posicao,
       a.situacao_atual,
       hp.preco AS preco_atual,
       ra.media,
       pa.pontos AS pontuacao_ultima_rodada
FROM atleta a
JOIN atleta_clube_rodada acr ON acr.atleta_id = a.id
JOIN clube c ON c.id = acr.clube_id
JOIN rodada r ON r.numero = acr.rodada_numero
JOIN historico_preco hp ON hp.atleta_id = a.id AND hp.rodada_numero = r.numero
LEFT JOIN vw_resumo_atleta ra ON ra.atleta_id = a.id
LEFT JOIN vw_pontos_atleta pa ON pa.atleta_id = a.id AND pa.rodada_numero = ra.ultima_rodada
WHERE r.estado = 'aberta' AND (a.situacao_atual = 'provavel' OR a.situacao_atual = 'duvida');

-- (b) Ranking acumulado por liga. A posição é 1 mais o número de técnicos à frente.
CREATE OR REPLACE VIEW vw_pontos_escalacao AS
SELECT e.tecnico_id,
       e.rodada_numero,
       e.data_confirmacao,
       f_pontos_escalacao(e.tecnico_id, e.rodada_numero) AS pontos
FROM escalacao e
JOIN rodada r ON r.numero = e.rodada_numero
WHERE e.estado = 'confirmada' AND r.estado = 'consolidada';

CREATE OR REPLACE VIEW vw_total_tecnico AS
SELECT t.id AS tecnico_id,
       COALESCE(SUM(pe.pontos), 0) AS pontuacao_acumulada
FROM tecnico t
LEFT JOIN vw_pontos_escalacao pe ON pe.tecnico_id = t.id
GROUP BY t.id;

CREATE OR REPLACE VIEW vw_total_participante AS
SELECT pl.liga_id, pl.tecnico_id, tt.pontuacao_acumulada
FROM participacao_liga pl
JOIN vw_total_tecnico tt ON tt.tecnico_id = pl.tecnico_id;

CREATE OR REPLACE VIEW vw_ranking_liga AS
SELECT atual.liga_id,
       atual.tecnico_id,
       atual.pontuacao_acumulada,
       1 + COUNT(outro.tecnico_id) AS posicao
FROM vw_total_participante atual
LEFT JOIN vw_total_participante outro ON outro.liga_id = atual.liga_id AND outro.pontuacao_acumulada > atual.pontuacao_acumulada
GROUP BY atual.liga_id, atual.tecnico_id, atual.pontuacao_acumulada;

-- (c) Cinco melhores por posição. No empate, o menor ID aparece primeiro.
CREATE OR REPLACE VIEW vw_ultima_rodada_preco AS
SELECT atleta_id, MAX(rodada_numero) AS rodada_numero
FROM historico_preco
GROUP BY atleta_id;

CREATE OR REPLACE VIEW vw_custo_beneficio AS
SELECT a.id AS atleta_id,
       a.posicao,
       a.apelido,
       ra.media AS media_pontos,
       COALESCE(hp.preco_apos_rodada, hp.preco) AS preco_atual,
       ra.media / COALESCE(hp.preco_apos_rodada, hp.preco) AS custo_beneficio
FROM atleta a
JOIN vw_resumo_atleta ra ON ra.atleta_id = a.id
JOIN vw_ultima_rodada_preco ur ON ur.atleta_id = a.id
JOIN historico_preco hp ON hp.atleta_id = ur.atleta_id AND hp.rodada_numero = ur.rodada_numero
WHERE ra.qtd_rodadas >= 3;

SELECT atual.posicao,
       atual.apelido,
       atual.media_pontos,
       atual.preco_atual,
       atual.custo_beneficio
FROM vw_custo_beneficio atual
LEFT JOIN vw_custo_beneficio outro
  ON outro.posicao = atual.posicao AND (
     outro.custo_beneficio > atual.custo_beneficio
     OR (outro.custo_beneficio = atual.custo_beneficio AND outro.atleta_id < atual.atleta_id)
 )
GROUP BY atual.atleta_id, atual.posicao, atual.apelido, atual.media_pontos,
         atual.preco_atual, atual.custo_beneficio
HAVING COUNT(outro.atleta_id) < 5
ORDER BY atual.posicao, atual.custo_beneficio DESC, atual.atleta_id;

-- (d) Top da rodada. Parâmetro de exemplo: rodada 5.
-- A confirmação mais antiga ganha o empate. O ID resolve horários idênticos.
SELECT pe.tecnico_id,
       t.nome_time,
       pe.pontos AS pontuacao,
       a.apelido AS capitao
FROM vw_pontos_escalacao pe
JOIN tecnico t ON t.id = pe.tecnico_id
JOIN escalacao_atleta ea ON ea.tecnico_id = pe.tecnico_id AND ea.rodada_numero = pe.rodada_numero AND ea.is_capitao
JOIN atleta a ON a.id = ea.atleta_id
LEFT JOIN vw_pontos_escalacao outro
  ON outro.rodada_numero = pe.rodada_numero AND (
     outro.pontos > pe.pontos
     OR (outro.pontos = pe.pontos AND outro.data_confirmacao < pe.data_confirmacao)
     OR (outro.pontos = pe.pontos AND outro.data_confirmacao = pe.data_confirmacao AND outro.tecnico_id < pe.tecnico_id)
 )
WHERE pe.rodada_numero = 5 AND outro.tecnico_id IS NULL;

-- (e) Clube com mais jogos sem sofrer gol nas últimas cinco rodadas consolidadas.
CREATE OR REPLACE VIEW vw_ultimas_cinco_rodadas AS
SELECT r.numero
FROM rodada r
LEFT JOIN rodada posterior ON posterior.numero > r.numero AND posterior.estado = 'consolidada'
WHERE r.estado = 'consolidada'
GROUP BY r.numero
HAVING COUNT(posterior.numero) < 5;

CREATE OR REPLACE VIEW vw_jogos_sem_sofrer_gol AS
SELECT c.id AS clube_id,
       c.nome,
       COUNT(*) AS jogos_sem_sofrer_gol
FROM clube c
JOIN partida p ON c.id = p.mandante_id OR c.id = p.visitante_id
JOIN vw_ultimas_cinco_rodadas r ON r.numero = p.rodada_numero
WHERE p.valida
  AND (
      (c.id = p.mandante_id AND p.placar_visitante = 0)
      OR (c.id = p.visitante_id AND p.placar_mandante = 0)
  )
GROUP BY c.id, c.nome;

SELECT atual.nome, atual.jogos_sem_sofrer_gol
FROM vw_jogos_sem_sofrer_gol atual
LEFT JOIN vw_jogos_sem_sofrer_gol outro
ON outro.jogos_sem_sofrer_gol > atual.jogos_sem_sofrer_gol OR (outro.jogos_sem_sofrer_gol = atual.jogos_sem_sofrer_gol AND outro.clube_id < atual.clube_id)
WHERE outro.clube_id IS NULL;

-- (f) Capitão mais escolhido em escalações confirmadas. Parâmetro: liga 1.
CREATE OR REPLACE VIEW vw_capitaes_liga AS
SELECT pl.liga_id, a.id AS atleta_id, a.apelido, COUNT(*) AS vezes_capitao
FROM participacao_liga pl
JOIN escalacao e ON e.tecnico_id = pl.tecnico_id
JOIN escalacao_atleta ea ON ea.tecnico_id = e.tecnico_id AND ea.rodada_numero = e.rodada_numero
JOIN atleta a ON a.id = ea.atleta_id
WHERE e.estado = 'confirmada' AND ea.is_capitao
GROUP BY pl.liga_id, a.id, a.apelido;

SELECT atual.apelido, atual.vezes_capitao
FROM vw_capitaes_liga atual
LEFT JOIN vw_capitaes_liga outro
  ON outro.liga_id = atual.liga_id
 AND (
     outro.vezes_capitao > atual.vezes_capitao
     OR (outro.vezes_capitao = atual.vezes_capitao AND outro.atleta_id < atual.atleta_id)
 )
WHERE atual.liga_id = 1 AND outro.atleta_id IS NULL;

-- (g) Técnicos que nunca confirmaram atleta do clube informado. Parâmetro: clube 10.
CREATE OR REPLACE VIEW vw_clube_escalado AS
SELECT e.tecnico_id, acr.clube_id
FROM escalacao e
JOIN escalacao_atleta ea ON ea.tecnico_id = e.tecnico_id AND ea.rodada_numero = e.rodada_numero
JOIN atleta_clube_rodada acr ON acr.atleta_id = ea.atleta_id AND acr.rodada_numero = ea.rodada_numero
WHERE e.estado = 'confirmada'
GROUP BY e.tecnico_id, acr.clube_id;

SELECT t.id, t.nome, t.nome_time
FROM tecnico t
LEFT JOIN vw_clube_escalado ce ON ce.tecnico_id = t.id AND ce.clube_id = 10
WHERE ce.tecnico_id IS NULL;

-- (h) Atletas acima da média da posição em todas as rodadas em que jogaram.
CREATE OR REPLACE VIEW vw_media_posicao AS
SELECT rodada_numero, posicao, SUM(pontos) / COUNT(*) AS media
FROM vw_pontos_atleta
GROUP BY rodada_numero, posicao;

CREATE OR REPLACE VIEW vw_atleta_nao_superou_media AS
SELECT pa.atleta_id
FROM vw_pontos_atleta pa
JOIN vw_media_posicao mp ON mp.rodada_numero = pa.rodada_numero
                          AND mp.posicao = pa.posicao
WHERE pa.pontos <= mp.media
GROUP BY pa.atleta_id;

SELECT a.id, a.apelido
FROM atleta a
JOIN vw_resumo_atleta ra ON ra.atleta_id = a.id
LEFT JOIN vw_atleta_nao_superou_media n ON n.atleta_id = a.id
WHERE n.atleta_id IS NULL;

-- (i) Evolução do patrimônio e diferença para o registro anterior. Parâmetro: técnico 1.
CREATE OR REPLACE VIEW vw_rodada_patrimonio_anterior AS
SELECT atual.tecnico_id,
       atual.rodada_numero,
       MAX(anterior.rodada_numero) AS rodada_anterior
FROM patrimonio_rodada atual
LEFT JOIN patrimonio_rodada anterior ON anterior.tecnico_id = atual.tecnico_id AND anterior.rodada_numero < atual.rodada_numero
GROUP BY atual.tecnico_id, atual.rodada_numero;

SELECT atual.rodada_numero,
       atual.patrimonio,
       atual.patrimonio - COALESCE(anterior.patrimonio, atual.patrimonio) AS variacao
FROM patrimonio_rodada atual
JOIN vw_rodada_patrimonio_anterior r ON r.tecnico_id = atual.tecnico_id AND r.rodada_numero = atual.rodada_numero
LEFT JOIN patrimonio_rodada anterior ON anterior.tecnico_id = atual.tecnico_id AND anterior.rodada_numero = r.rodada_anterior
WHERE atual.tecnico_id = 1
ORDER BY atual.rodada_numero;

-- (j) Ligas com três ou mais participantes e média acima da média geral.
CREATE OR REPLACE VIEW vw_media_geral AS
SELECT SUM(pontuacao_acumulada) / COUNT(*) AS media
FROM vw_total_tecnico
HAVING COUNT(*) > 0;

CREATE OR REPLACE VIEW vw_media_liga AS
SELECT l.id AS liga_id, l.nome,
       SUM(tp.pontuacao_acumulada) / COUNT(*) AS media_liga
FROM liga l
JOIN vw_total_participante tp ON tp.liga_id = l.id
GROUP BY l.id, l.nome
HAVING COUNT(*) >= 3;

SELECT ml.liga_id, ml.nome, ml.media_liga
FROM vw_media_liga ml
JOIN vw_media_geral mg ON ml.media_liga > mg.media;

-- (k) Melhor atleta de cada posição até C$ 12,00. Parâmetro: rodada 4.
-- Em caso de empate na posição, escolhe o menor ID.
CREATE OR REPLACE VIEW vw_candidatos_selecao AS
SELECT pa.atleta_id, pa.apelido, pa.posicao, pa.rodada_numero, hp.preco, pa.pontos
FROM vw_pontos_atleta pa
JOIN historico_preco hp ON hp.atleta_id = pa.atleta_id AND hp.rodada_numero = pa.rodada_numero
WHERE hp.preco <= 12.00;

CREATE OR REPLACE VIEW vw_selecao_rodada AS
SELECT atual.atleta_id, atual.apelido, atual.posicao, atual.rodada_numero, atual.preco, atual.pontos
FROM vw_candidatos_selecao atual
LEFT JOIN vw_candidatos_selecao outro ON outro.rodada_numero = atual.rodada_numero AND outro.posicao = atual.posicao AND (
     outro.pontos > atual.pontos OR (outro.pontos = atual.pontos AND outro.atleta_id < atual.atleta_id)
 )
WHERE outro.atleta_id IS NULL;

CREATE OR REPLACE VIEW vw_custo_selecao AS
SELECT rodada_numero, SUM(preco) AS custo_total
FROM vw_selecao_rodada
GROUP BY rodada_numero;

SELECT s.posicao, s.apelido, s.preco, s.pontos, c.custo_total
FROM vw_selecao_rodada s
JOIN vw_custo_selecao c ON c.rodada_numero = s.rodada_numero
WHERE s.rodada_numero = 4
ORDER BY s.posicao;

/*(a) Crie a visão do mercado: para cada atleta disponível para escalação na rodada aberta,
o apelido, o clube, a posição, a situação, o preço atual, a média e a pontuação na última
rodada consolidada em que entrou em campo*/

CREATE OR REPLACE VIEW vw_mercado AS
SELECT 
    a.id AS atleta_id,
    a.apelido,
    c.nome AS clube,
    a.posicao,
    a.situacao_atual,
    hp.preco AS preco_atual,
   (SELECT AVG(f_pontos_atleta(ap.atleta_id, p.rodada_numero)) 
     FROM atleta_partida ap 
     JOIN partida p ON ap.partida_id = p.id 
     WHERE ap.atleta_id = a.id AND ap.entrou_em_campo = TRUE) AS media,
     (SELECT f_pontos_atleta(ap.atleta_id, p.rodada_numero)
     FROM atleta_partida ap 
     JOIN partida p ON ap.partida_id = p.id 
     JOIN rodada r ON p.rodada_numero = r.numero
     WHERE ap.atleta_id = a.id AND ap.entrou_em_campo = TRUE AND r.estado = 'consolidada'
     ORDER BY p.rodada_numero DESC LIMIT 1) AS pontuacao_ultima_rodada
FROM atleta a
JOIN atleta_clube_rodada acr ON a.id = acr.atleta_id
JOIN clube c ON acr.clube_id = c.id
JOIN rodada r_aberta ON acr.rodada_numero = r_aberta.numero AND r_aberta.estado = 'aberta'
JOIN historico_preco hp ON hp.atleta_id = a.id AND hp.rodada_numero = r_aberta.numero;


/*(b) Crie a visão do ranking: para cada liga e cada técnico participante, a pontuação acumulada e a posição do técnico na liga. Técnicos empatados ocupam a mesma posição.*/


CREATE OR REPLACE VIEW vw_ranking_liga AS
WITH pontuacao_tecnicos AS (
    SELECT 
        pl.liga_id,
        pl.tecnico_id,
        COALESCE(SUM(f_pontos_escalacao(e.tecnico_id, e.rodada_numero)), 0) AS pontuacao_acumulada
    FROM participacao_liga pl
    LEFT JOIN escalacao e ON pl.tecnico_id = e.tecnico_id AND e.estado = 'confirmada'
    GROUP BY pl.liga_id, pl.tecnico_id
)
SELECT 
    liga_id,
    tecnico_id,
    pontuacao_acumulada,
    RANK() OVER (PARTITION BY liga_id ORDER BY pontuacao_acumulada DESC) AS posicao
FROM pontuacao_tecnicos;




/*(c) Os 5 atletas de cada posição com melhor custo-benefício (média de pontos dividida pelo
preço atual), considerando apenas atletas que entraram em campo em pelo menos 3
rodadas.*/

WITH stats_atletas AS (
    SELECT 
        a.id,
        a.apelido,
        a.posicao,
        COUNT(ap.partida_id) AS qtd_rodadas,
        AVG(f_pontos_atleta(a.id, p.rodada_numero)) AS media_pontos,
        (SELECT hp.preco FROM historico_preco hp WHERE hp.atleta_id = a.id ORDER BY hp.rodada_numero DESC LIMIT 1) AS preco_atual
    FROM atleta a
    JOIN atleta_partida ap ON a.id = ap.atleta_id
    JOIN partida p ON ap.partida_id = p.id
    WHERE ap.entrou_em_campo = TRUE
    GROUP BY a.id, a.apelido, a.posicao
    HAVING COUNT(DISTINCT p.rodada_numero) >= 3
),
custo_beneficio AS (
    SELECT 
        id, apelido, posicao, media_pontos, preco_atual,
        (media_pontos / NULLIF(preco_atual, 0)) AS cb,
        ROW_NUMBER() OVER (PARTITION BY posicao ORDER BY (media_pontos / NULLIF(preco_atual, 0)) DESC) as rn
    FROM stats_atletas
)
SELECT posicao, apelido, media_pontos, preco_atual, cb
FROM custo_beneficio
WHERE rn <= 5;


/* (d) O “top da rodada”: para uma rodada consolidada, o técnico de maior pontuação, o
nome do seu time, a pontuação e o capitão escolhido. Em caso de empate, vence quem
confirmou a escalação primeiro.*/



SELECT 
    e.tecnico_id,
    t.nome_time,
    f_pontos_escalacao(e.tecnico_id, e.rodada_numero) AS pontuacao,
    (SELECT a.apelido FROM escalacao_atleta ea JOIN atleta a ON ea.atleti_id = a.id WHERE ea.tecnico_id = e.tecnico_id AND ea.rodada_numero = e.rodada_numero AND ea.is_capitao = TRUE) AS capitao
FROM escalacao e
JOIN tecnico t ON e.tecnico_id = t.id
WHERE e.rodada_numero = 5 -- Parâmetro: número da rodada
  AND e.estado = 'confirmada'
ORDER BY pontuacao DESC, e.data_confirmacao ASC
LIMIT 1;


/*-- (e) O clube com mais jogos sem sofrer gol nas últimas 5 rodadas consolidadas, calculado a
partir dos placares das partidas.*/

WITH ultimas_rodadas AS (
    SELECT numero FROM rodada WHERE estado = 'consolidada' ORDER BY numero DESC LIMIT 5
),
jogos_sem_gol AS (
    SELECT mandante_id AS clube_id FROM partida p JOIN ultimas_rodadas ur ON p.rodada_numero = ur.numero WHERE p.valida = TRUE AND p.placar_visitante = 0
    UNION ALL
    SELECT visitante_id AS clube_id FROM partida p JOIN ultimas_rodadas ur ON p.rodada_numero = ur.numero WHERE p.valida = TRUE AND p.placar_mandante = 0
)
SELECT c.nome, COUNT(*) AS jogos_sem_sofrer_gol
FROM jogos_sem_gol jsg
JOIN clube c ON jsg.clube_id = c.id
GROUP BY c.id, c.nome
ORDER BY jogos_sem_sofrer_gol DESC
LIMIT 1;



/*(f) O atleta mais escolhido como capitão dentro de uma liga, com a quantidade de vezes.*/

SELECT a.apelido, COUNT(*) AS vezes_capitao
FROM escalacao_atleta ea
JOIN participacao_liga pl ON ea.tecnico_id = pl.tecnico_id
JOIN atleta a ON ea.atleta_id = a.id
WHERE pl.liga_id = 1 -- Parâmetro: ID da liga
  AND ea.is_capitao = TRUE
GROUP BY a.id, a.apelido
ORDER BY vezes_capitao DESC
LIMIT 1;


-- (g) Os técnicos que nunca escalaram nenhum atleta de um clube informado.
SELECT t.id, t.nome, t.nome_time
FROM tecnico t
WHERE NOT EXISTS (
    SELECT 1 
    FROM escalacao_atleta ea
    JOIN atleta_clube_rodada acr ON ea.atleta_id = acr.atleta_id AND ea.rodada_numero = acr.rodada_numero
    WHERE ea.tecnico_id = t.id AND acr.clube_id = 10 -- Parâmetro: ID do clube
);


/*(h) Os atletas que, em todas as rodadas consolidadas em que entraram em campo, pontuaram acima da média da sua posição naquela rodada.*/

WITH media_posicao_rodada AS (
    SELECT 
        p.rodada_numero,
        a.posicao,
        AVG(f_pontos_atleta(a.id, p.rodada_numero)) AS media_pos
    FROM atleta_partida ap
    JOIN partida p ON ap.partida_id = p.id
    JOIN atleta a ON ap.atleta_id = a.id
    JOIN rodada r ON p.rodada_numero = r.numero
    WHERE ap.entrou_em_campo = TRUE AND r.estado = 'consolidada'
    GROUP BY p.rodada_numero, a.posicao
),
desempenho_atleta AS (
    SELECT 
        ap.atleta_id,
        p.rodada_numero,
        f_pontos_atleta(ap.atleta_id, p.rodada_numero) AS pts,
        mpr.media_pos
    FROM atleta_partida ap
    JOIN partida p ON ap.partida_id = p.id
    JOIN atleta a ON ap.atleta_id = a.id
    JOIN rodada r ON p.rodada_numero = r.numero
    JOIN media_posicao_rodada mpr ON p.rodada_numero = mpr.rodada_numero AND a.posicao = mpr.posicao
    WHERE ap.entrou_em_campo = TRUE AND r.estado = 'consolidada'
)
SELECT DISTINCT a.id, a.apelido
FROM atleta a
WHERE NOT EXISTS (
    SELECT 1 FROM desempenho_atleta da 
    WHERE da.atleta_id = a.id AND da.pts <= da.media_pos
)
AND EXISTS (
    SELECT 1 FROM desempenho_atleta da WHERE da.atleta_id = a.id
);


-- (i) A evolução do patrimônio de um técnico rodada a rodada, com a variação em relação à
rodada anterior.
SELECT 
    rodada_numero,
    patrimonio,
    patrimonio - LAG(patrimonio, 1, patrimonio) OVER (ORDER BY rodada_numero) AS variacao
FROM patrimonio_rodada
WHERE tecnico_id = 1 -- Parâmetro: ID do técnico
ORDER BY rodada_numero;


/*(j) As ligas com pelo menos 3 participantes cuja pontuação média por técnico, no acumulado, seja maior que a média geral de todos os técnicos do sistema.*/

WITH media_tecnicos AS (
    SELECT tecnico_id, COALESCE(SUM(f_pontos_escalacao(tecnico_id, rodada_numero)), 0) AS total_pts
    FROM escalacao WHERE estado = 'confirmada'
    GROUP BY tecnico_id
),
media_geral AS (
    SELECT AVG(total_pts) AS geral FROM media_tecnicos
),
media_por_liga AS (
    SELECT 
        l.id,
        l.nome,
        COUNT(pl.tecnico_id) AS qtd_participantes,
        AVG(mt.total_pts) AS media_liga
    FROM liga l
    JOIN participacao_liga pl ON l.id = pl.liga_id
    JOIN media_tecnicos mt ON pl.tecnico_id = mt.tecnico_id
    GROUP BY l.id, l.nome
    HAVING COUNT(pl.tecnico_id) >= 3
)
SELECT mpl.id, mpl.nome, mpl.media_liga
FROM media_por_liga mpl
CROSS JOIN media_geral mg
WHERE mpl.media_liga > mg.geral;


/*(k) A “seleção da rodada” simplificada: para uma rodada consolidada, o atleta de maior
pontuação de cada posição, considerando apenas atletas cujo preço naquela rodada era
de no máximo C$ 12,00, e o custo total desse time.*/

WITH atletas_filtrados AS (
    SELECT 
        a.id, a.apelido, a.posicao,
        hp.preco,
        f_pontos_atleta(a.id, 4) AS pontos, -- Parâmetro: rodada
        ROW_NUMBER() OVER (PARTITION BY a.posicao ORDER BY f_pontos_atleta(a.id, 4) DESC) as rn
    FROM atleta a
    JOIN historico_preco hp ON a.id = hp.atleta_id AND hp.rodada_numero = 4
    JOIN atleta_partida ap ON a.id = ap.atleta_id
    JOIN partida p ON ap.partida_id = p.id
    WHERE p.rodada_numero = 4 AND ap.entrou_em_campo = TRUE AND hp.preco <= 12.00
)
SELECT posicao, apelido, preco, pontos
FROM atletas_filtrados
WHERE rn = 1;






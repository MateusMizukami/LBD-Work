SET search_path TO liga_facom;

-- 1. Tipos de scout.
INSERT INTO tipo_scout (sigla, descricao, valor_pontos)
VALUES
    ('G',  'Gol', 8.00),
    ('A',  'Assistência', 5.00),
    ('FT', 'Finalização na trave',3.00),
    ('FD', 'Finalização defendida',1.20),
    ('FF', 'Finalização para fora',0.80),
    ('FS', 'Falta sofrida', 0.50),
    ('PS', 'Pênalti sofrido', 1.00),
    ('DS', 'Desarme', 1.50),
    ('SG', 'Jogo sem sofrer gol', 5.00),
    ('DE', 'Defesa', 1.30),
    ('DP', 'Defesa de pênalti',7.00),
    ('GS', 'Gol sofrido', -1.00),
    ('FC', 'Falta cometida', -0.30),
    ('I',  'Impedimento',-0.10),
    ('CA', 'Cartão amarelo',-1.00),
    ('CV', 'Cartão vermelho',-3.00),
    ('GC', 'Gol contra',-3.00),
    ('PC', 'Pênalti cometido',-1.00),
    ('PP', 'Pênalti perdido',-4.00);

-- 2. Posições em que cada scout pode pontuar.
INSERT INTO tipo_scout_posicao (sigla_scout, posicao)
SELECT s.sigla, p.posicao
FROM tipo_scout AS s
CROSS JOIN (VALUES ('gol'), ('lat'), ('zag'), ('mei'), ('ata'), ('tec'))
    AS p(posicao)
WHERE s.sigla NOT IN ('SG', 'DE', 'DP', 'GS')
UNION ALL
SELECT restricao.sigla, restricao.posicao
FROM (VALUES
    ('SG', 'gol'),
    ('SG', 'lat'),
    ('SG', 'zag'),
    ('DE', 'gol'),
    ('DP', 'gol'),
    ('GS', 'gol')
) AS restricao(sigla, posicao);

-- 3. Técnicos fictícios. Gera o ID e inicia o patrimônio em 100,00.
INSERT INTO tecnico (nome, email, apelido_exibicao, nome_time)
VALUES
    ('Ana Clara','ana@example.com', 'Ana','Bits FC'),
    ('Matheus Henrique', 'matheus@example.com', 'Matheus', 'Rubro FC'),
    ('Camila Franco', 'camila@example.com','Camila', 'Monster United'),
    ('Erik Alves', 'erik@example.com', 'Erik', 'Índice FC'),
    ('Elisa Arrocha', 'elisa@example.com','Elisa', 'Criativo FC'),
    ('Ricardo Ikeda', 'ricardo@example.com', 'Ricardo','Cartoletas'),
    ('Gabriela Rossi','gabriela@example.com','Gabi', 'Atlética FACOM'),
    ('Hugo Souza', 'hugo@example.com', 'Hugo', 'Rebaixados FC');

-- 4. Duas ligas públicas e uma privada.
INSERT INTO liga (nome, descricao, codigo_convite, limite_participantes, tipo, dono_id)
SELECT dados.nome, dados.descricao, dados.codigo, dados.limite, dados.tipo, t.id
FROM (VALUES
    ('Liga FACOM', 'Liga aberta da facom','FACOM2026',8, 'publica', 'ana@example.com'),
    ('Liga dos engenheiros', 'Liga dos exatos','Eng26',4, 'privada', 'matheus@example.com'),
    ('Copa do Laboratório', 'Só cientistas','LAB2026',6, 'publica', 'camila@example.com')
) AS dados(nome, descricao, codigo, limite, tipo, email_dono)
JOIN tecnico AS t ON t.email = dados.email_dono;

-- 5. Participações iniciais, incluindo os donos.
INSERT INTO participacao_liga (tecnico_id, liga_id)
SELECT t.id, l.id
FROM (VALUES
    ('FACOM2026','ana@example.com'),
    ('FACOM2026','matheus@example.com'),
    ('FACOM2026','camila@example.com'),
    ('FACOM2026','erik@example.com'),
    ('Eng26','matheus@example.com'),
    ('Eng26','elisa@example.com'),
    ('Eng26', 'ricardo@example.com'),
    ('LAB2026','camila@example.com'),
    ('LAB2026', 'gabriela@example.com'),
    ('LAB2026','hugo@example.com')
) AS dados(codigo, email)
JOIN tecnico AS t ON t.email = dados.email
JOIN liga AS l ON l.codigo_convite = dados.codigo;

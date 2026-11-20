SET search_path TO liga_facom;

INSERT INTO tipo_scout (sigla, descricao, valor_pontos) VALUES
    ('G',  'Gol',                                      8.00),
    ('A',  'Assistência',                              5.00),
    ('FT', 'Finalização na trave',                     3.00),
    ('FD', 'Finalização defendida pelo goleiro',        1.20),
    ('FF', 'Finalização para fora',                    0.80),
    ('FS', 'Falta sofrida',                            0.50),
    ('PS', 'Pênalti sofrido',                          1.00),
    ('DS', 'Desarme',                                  1.50),
    ('SG', 'Jogo sem sofrer gol',                      5.00),
    ('DE', 'Defesa',                                   1.30),
    ('DP', 'Defesa de pênalti',                        7.00),
    ('GS', 'Gol sofrido',                             -1.00),
    ('FC', 'Falta cometida',                          -0.30),
    ('I',  'Impedimento',                             -0.10),
    ('CA', 'Cartão amarelo',                          -1.00),
    ('CV', 'Cartão vermelho',                         -3.00),
    ('GC', 'Gol contra',                              -3.00),
    ('PC', 'Pênalti cometido',                        -1.00),
    ('PP', 'Pênalti perdido',                         -4.00)
ON CONFLICT (sigla) DO UPDATE SET
    descricao = EXCLUDED.descricao,
    valor_pontos = EXCLUDED.valor_pontos;

INSERT INTO tipo_scout_posicao (sigla_scout, posicao)
SELECT s.sigla, p.posicao
FROM tipo_scout s
CROSS JOIN (VALUES ('gol'), ('lat'), ('zag'), ('mei'), ('ata'), ('tec')) AS p(posicao)
WHERE s.sigla NOT IN ('SG', 'DE', 'DP', 'GS')
ON CONFLICT (sigla_scout, posicao) DO NOTHING;

INSERT INTO tipo_scout_posicao (sigla_scout, posicao) VALUES
    ('SG', 'gol'), ('SG', 'lat'), ('SG', 'zag'),
    ('DE', 'gol'),
    ('DP', 'gol'),
    ('GS', 'gol')
ON CONFLICT (sigla_scout, posicao) DO NOTHING;

INSERT INTO tecnico (nome, email, apelido_exibicao, nome_time)
VALUES
    ('Ana Souza',       'ana.souza@exemplo.com',       'Ana',       'As Feras'),
    ('Bruno Lima',      'bruno.lima@exemplo.com',      'Brunão',    'Lima FC'),
    ('Carla Mendes',    'carla.mendes@exemplo.com',    'Carlinha',  'Mendes United'),
    ('Diego Alves',     'diego.alves@exemplo.com',     'Diegão',    'Resenha FC'),
    ('Eduarda Costa',  'eduarda.costa@exemplo.com',   'Duda',      'Duda Stars'),
    ('Felipe Rocha',   'felipe.rocha@exemplo.com',    'Felipe',    'Rocha Team'),
    ('Gabriela Nunes', 'gabriela.nunes@exemplo.com',  'Gabi',      'Gabi Gol'),
    ('Heitor Martins', 'heitor.martins@exemplo.com',  'Heitor',    'Martins FC')
ON CONFLICT (email) DO NOTHING;

INSERT INTO liga (nome, descricao, codigo_convite, limite_participantes, tipo, dono_id)
SELECT v.nome, v.descricao, v.codigo_convite, v.limite_participantes, v.tipo, t.id
FROM (VALUES
    ('Liga FACOM Aberta', 'Liga pública para todos os participantes.', NULL::text, 8, 'publica', 'ana.souza@exemplo.com'),
    ('Desafio dos Amigos', 'Liga pública de demonstração.', NULL::text, 8, 'publica', 'bruno.lima@exemplo.com'),
    ('Liga Secreta', 'Liga privada com convite.', 'FACOM2026', 8, 'privada', 'carla.mendes@exemplo.com')
) AS v(nome, descricao, codigo_convite, limite_participantes, tipo, email_dono)
JOIN tecnico t ON t.email = v.email_dono
WHERE NOT EXISTS (SELECT 1 FROM liga l_existente WHERE l_existente.nome = v.nome);

INSERT INTO participacao_liga (tecnico_id, liga_id)
SELECT t.id, l.id
FROM (VALUES
    ('Liga FACOM Aberta', 'ana.souza@exemplo.com'),
    ('Liga FACOM Aberta', 'bruno.lima@exemplo.com'),
    ('Liga FACOM Aberta', 'carla.mendes@exemplo.com'),
    ('Liga FACOM Aberta', 'diego.alves@exemplo.com'),
    ('Liga FACOM Aberta', 'eduarda.costa@exemplo.com'),
    ('Liga FACOM Aberta', 'felipe.rocha@exemplo.com'),
    ('Liga FACOM Aberta', 'gabriela.nunes@exemplo.com'),
    ('Liga FACOM Aberta', 'heitor.martins@exemplo.com'),
    ('Desafio dos Amigos', 'bruno.lima@exemplo.com'),
    ('Desafio dos Amigos', 'ana.souza@exemplo.com'),
    ('Desafio dos Amigos', 'diego.alves@exemplo.com'),
    ('Desafio dos Amigos', 'felipe.rocha@exemplo.com'),
    ('Liga Secreta', 'carla.mendes@exemplo.com'),
    ('Liga Secreta', 'ana.souza@exemplo.com'),
    ('Liga Secreta', 'gabriela.nunes@exemplo.com')
) AS p(nome_liga, email_tecnico)
JOIN liga l ON l.nome = p.nome_liga
JOIN tecnico t ON t.email = p.email_tecnico
ON CONFLICT (tecnico_id, liga_id) DO NOTHING;
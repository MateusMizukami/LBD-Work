SET search_path TO liga_facom;

-- Índices para junções frequentes e filtros por rodada/estado.
CREATE INDEX IF NOT EXISTS ix_partida_rodada_valida ON partida(rodada_numero, valida);
CREATE INDEX IF NOT EXISTS ix_atleta_partida_partida ON atleta_partida(partida_id, atleta_id);
CREATE INDEX IF NOT EXISTS ix_scout_partida_atleta ON atleta_partida_scout(partida_id, atleta_id);
CREATE INDEX IF NOT EXISTS ix_escalacao_rodada_estado ON escalacao(rodada_numero, estado);
CREATE INDEX IF NOT EXISTS ix_escalacao_atleta_rodada ON escalacao_atleta(rodada_numero, atleta_id);
CREATE INDEX IF NOT EXISTS ix_historico_preco_rodada ON historico_preco(rodada_numero, atleta_id);
CREATE INDEX IF NOT EXISTS ix_patrimonio_tecnico_rodada ON patrimonio_rodada(tecnico_id, rodada_numero);
CREATE INDEX IF NOT EXISTS ix_acr_rodada_clube ON atleta_clube_rodada(rodada_numero, clube_id);
CREATE INDEX IF NOT EXISTS ix_participacao_liga ON participacao_liga(liga_id, tecnico_id);

-- Chrono Shards 8.7.0 — Loja do Mauro + Bestiário autoritativos
-- Execute uma única vez após as migrations 015 e 016.
-- O cliente solicita ações; preços, rotação, recompensas, propriedade e resgates
-- são calculados e persistidos exclusivamente pelo PostgreSQL.

begin;

create extension if not exists pgcrypto;

alter table public.chrono_player_state
  add column if not exists mauro_authority_enabled boolean not null default false,
  add column if not exists bestiary_authority_enabled boolean not null default false,
  add column if not exists collection_authority_enabled_at timestamptz;

create table if not exists public.chrono_mauro_skin_catalog (
  skin_id text primary key,
  character_key text not null,
  rarity text not null check (rarity in ('base','common','rare','epic')),
  name text not null,
  description text not null,
  cost bigint not null check (cost >= 0),
  color text not null,
  accent text not null
);

create table if not exists public.chrono_mauro_augment_catalog (
  augment_id text primary key,
  character_key text not null,
  name text not null,
  icon text not null,
  color text not null,
  description text not null,
  cost bigint not null default 170 check (cost >= 0)
);

create table if not exists public.chrono_mauro_relic_catalog (
  relic_id text primary key,
  name text not null,
  description text not null,
  cost bigint not null check (cost >= 0)
);

create table if not exists public.chrono_mauro_power_catalog (
  power_id text primary key,
  name text not null,
  rarity text not null check (rarity in ('COMUM','RARO','ÉPICO','LENDÁRIO','MÍTICO')),
  description text not null,
  weight numeric not null default 1 check (weight > 0)
);

create table if not exists public.chrono_bestiary_catalog (
  entry_id text primary key,
  tab text not null check (tab in ('general','rift','doom')),
  group_name text not null,
  name text not null,
  required_kills bigint not null check (required_kills > 0),
  relic_reward bigint not null check (relic_reward > 0)
);

create table if not exists public.chrono_player_inventory (
  user_id uuid primary key references auth.users(id) on delete cascade,
  skins text[] not null default '{}',
  augments text[] not null default '{}',
  permanent_relics text[] not null default '{}',
  catalog_powerups text[] not null default '{}',
  selected_skins jsonb not null default '{}'::jsonb,
  imported_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.chrono_player_mauro (
  user_id uuid primary key references auth.users(id) on delete cascade,
  rotation_epoch bigint not null default -1,
  rotation_items jsonb not null default '[]'::jsonb,
  sold_slots jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(rotation_items) = 'array'),
  check (jsonb_typeof(sold_slots) = 'object')
);

create table if not exists public.chrono_player_bestiary (
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_id text not null references public.chrono_bestiary_catalog(entry_id) on update cascade on delete restrict,
  kills bigint not null default 0 check (kills >= 0),
  claimed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, entry_id)
);

create table if not exists public.chrono_bestiary_run_counters (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.chrono_game_sessions(id) on delete cascade,
  type_kills jsonb not null default '{}'::jsonb,
  finalized boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, session_id),
  check (jsonb_typeof(type_kills) = 'object')
);

create index if not exists chrono_player_bestiary_entry_idx on public.chrono_player_bestiary(entry_id, kills desc);
create index if not exists chrono_bestiary_run_updated_idx on public.chrono_bestiary_run_counters(updated_at desc);

insert into public.chrono_mauro_skin_catalog(skin_id,character_key,rarity,name,description,cost,color,accent) values
('assault_default','assault','base','Visual Padrão','Visual base usado em batalha.',0,'#61dafb','#eaf8ff'),
('assault_common_1','assault','common','Azul Nebulosa — Assault','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('assault_common_2','assault','common','Verde Rift — Assault','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('assault_common_3','assault','common','Rubro Solar — Assault','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('assault_rare_1','assault','rare','Legião Vulcânica','Armadura de assalto forjada em magma, com placas eruptivas e núcleo ígneo.',80,'#ff6b2f','#ffd36b'),
('sniper_default','sniper','base','Visual Padrão','Visual base usado em batalha.',0,'#ffd166','#eaf8ff'),
('sniper_common_1','sniper','common','Azul Nebulosa — Sniper','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('sniper_common_2','sniper','common','Verde Rift — Sniper','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('sniper_common_3','sniper','common','Rubro Solar — Sniper','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('sniper_rare_1','sniper','rare','Espectro Boreal','Atirador fantasma de gelo, mira polar e lâmina de precisão cristalina.',80,'#87e7ff','#eafcff'),
('engineer_default','engineer','base','Visual Padrão','Visual base usado em batalha.',0,'#8ff8ff','#eaf8ff'),
('engineer_common_1','engineer','common','Azul Nebulosa — Artífice ️','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('engineer_common_2','engineer','common','Verde Rift — Artífice ️','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('engineer_common_3','engineer','common','Rubro Solar — Artífice ️','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('engineer_rare_1','engineer','rare','Forja Celeste','Engenheiro de oficina orbital, satélites mecânicos e circuitos dourados.',80,'#54d9ff','#ffd166'),
('mage_default','mage','base','Visual Padrão','Visual base usado em batalha.',0,'#c6a0ff','#eaf8ff'),
('mage_common_1','mage','common','Azul Nebulosa — Void Mage','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('mage_common_2','mage','common','Verde Rift — Void Mage','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('mage_common_3','mage','common','Rubro Solar — Void Mage','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('mage_rare_1','mage','rare','Arcanista do Vazio','Manto arcano instável, runas orbitais e cristais extradimensionais.',80,'#a875ff','#e8d8ff'),
('ronin_default','ronin','base','Visual Padrão','Visual base usado em batalha.',0,'#ffd166','#eaf8ff'),
('ronin_common_1','ronin','common','Azul Nebulosa — Chrono Ronin ️','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('ronin_common_2','ronin','common','Verde Rift — Chrono Ronin ️','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('ronin_common_3','ronin','common','Rubro Solar — Chrono Ronin ️','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('ronin_rare_1','ronin','rare','Oni Dourado','Armadura ritual de oni, chifres dourados e lâmina cerimonial.',80,'#ffba52','#fff0bf'),
('alchemist_default','alchemist','base','Visual Padrão','Visual base usado em batalha.',0,'#b6ff7a','#eaf8ff'),
('alchemist_common_1','alchemist','common','Azul Nebulosa — Alquimista ☣️','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('alchemist_common_2','alchemist','common','Verde Rift — Alquimista ☣️','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('alchemist_common_3','alchemist','common','Rubro Solar — Alquimista ☣️','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('alchemist_rare_1','alchemist','rare','Praga Esmeralda','Traje de peste viva com frascos orbitais e vapores alquímicos.',80,'#32d98b','#d9ff8e'),
('reaper_default','reaper','base','Visual Padrão','Visual base usado em batalha.',0,'#ff7b9c','#eaf8ff'),
('reaper_common_1','reaper','common','Azul Nebulosa — Reaper ⚔️','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('reaper_common_2','reaper','common','Verde Rift — Reaper ⚔️','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('reaper_common_3','reaper','common','Rubro Solar — Reaper ⚔️','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('reaper_rare_1','reaper','rare','Funeral Carmesim','Caixão ritual, foice espectral e procissão de almas carmesins.',80,'#ff375f','#ffe3eb'),
('colonel_default','colonel','base','Visual Padrão','Visual base usado em batalha.',0,'#78d66b','#eaf8ff'),
('colonel_common_1','colonel','common','Azul Nebulosa — Coronel','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('colonel_common_2','colonel','common','Verde Rift — Coronel','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('colonel_common_3','colonel','common','Rubro Solar — Coronel','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('colonel_rare_1','colonel','rare','Marechal Celeste','Comandante de guerra aérea com insígnias, asas táticas e mira de bombardeio.',80,'#73cfff','#ffe08c'),
('bomber_default','bomber','base','Visual Padrão','Visual base usado em batalha.',0,'#ff9b3d','#eaf8ff'),
('bomber_common_1','bomber','common','Azul Nebulosa — Bombardeiro','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('bomber_common_2','bomber','common','Verde Rift — Bombardeiro','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('bomber_common_3','bomber','common','Rubro Solar — Bombardeiro','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('bomber_rare_1','bomber','rare','Demolidor Magma','Demolidor vulcânico com cargas incandescentes e coroa de detonação.',80,'#ff6f32','#ffd09a'),
('archer_default','archer','base','Visual Padrão','Visual base usado em batalha.',0,'#ffd166','#eaf8ff'),
('archer_common_1','archer','common','Azul Nebulosa — Arqueiro do Chrono','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('archer_common_2','archer','common','Verde Rift — Arqueiro do Chrono','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('archer_common_3','archer','common','Rubro Solar — Arqueiro do Chrono','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('archer_rare_1','archer','rare','Caçadora Astral','Arqueira lunar com arco crescente e flechas guiadas por constelações.',80,'#6bc8ff','#e9d1ff'),
('chronoHero_default','chronoHero','base','Visual Padrão','Visual base usado em batalha.',0,'#5fffee','#eaf8ff'),
('chronoHero_common_1','chronoHero','common','Azul Nebulosa — Chrono-Hero','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('chronoHero_common_2','chronoHero','common','Verde Rift — Chrono-Hero','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('chronoHero_common_3','chronoHero','common','Rubro Solar — Chrono-Hero','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('chronoHero_rare_1','chronoHero','rare','Oráculo Fraturado','Guardião de relógios partidos, prismas temporais e ponteiros orbitais.',80,'#8d64ff','#ffe38c'),
('shadowChild_default','shadowChild','base','Visual Padrão','Visual base usado em batalha.',0,'#ff1f3d','#eaf8ff'),
('shadowChild_common_1','shadowChild','common','Azul Nebulosa — Filho das Trevas','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('shadowChild_common_2','shadowChild','common','Verde Rift — Filho das Trevas','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('shadowChild_common_3','shadowChild','common','Rubro Solar — Filho das Trevas','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('shadowChild_rare_1','shadowChild','rare','Arauto Abissal','Forma demoníaca coroada por chifres, asas de sombra e olhos do abismo.',80,'#ff183f','#c99bff'),
('moonSlayer_default','moonSlayer','base','Visual Padrão','Visual base usado em batalha.',0,'#cdb7ff','#eaf8ff'),
('moonSlayer_common_1','moonSlayer','common','Azul Nebulosa — Exterminador de Luas ☾','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('moonSlayer_common_2','moonSlayer','common','Verde Rift — Exterminador de Luas ☾','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('moonSlayer_common_3','moonSlayer','common','Rubro Solar — Exterminador de Luas ☾','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('moonSlayer_rare_1','moonSlayer','rare','Lua de Marfim','Espadachim lunar coberto por crescente de marfim e estilhaços de lua.',80,'#c7d3ff','#ffffff'),
('ricocheteador_default','ricocheteador','base','Visual Padrão','Visual base usado em batalha.',0,'#ffd166','#eaf8ff'),
('ricocheteador_common_1','ricocheteador','common','Azul Nebulosa — Ricocheteador ◉','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('ricocheteador_common_2','ricocheteador','common','Verde Rift — Ricocheteador ◉','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('ricocheteador_common_3','ricocheteador','common','Rubro Solar — Ricocheteador ◉','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('ricocheteador_rare_1','ricocheteador','rare','Cassino Quântico','Duelista probabilístico com fichas orbitais, dados e ricochetes impossíveis.',80,'#ffd166','#65d8ff'),
('stellarEmperor_default','stellarEmperor','base','Visual Padrão','Visual base usado em batalha.',0,'#ffd166','#eaf8ff'),
('stellarEmperor_common_1','stellarEmperor','common','Azul Nebulosa — Emperador Estelar ☀️','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('stellarEmperor_common_2','stellarEmperor','common','Verde Rift — Emperador Estelar ☀️','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('stellarEmperor_common_3','stellarEmperor','common','Rubro Solar — Emperador Estelar ☀️','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('stellarEmperor_rare_1','stellarEmperor','rare','Relicário — Emperador Estelar ☀️','Modelo raro único do personagem.',80,'#ffb8ff','#fff'),
('nefalem_default','nefalem','base','Visual Padrão','Visual base usado em batalha.',0,'#ff4d5f','#eaf8ff'),
('nefalem_common_1','nefalem','common','Azul Nebulosa — Nefalem ⚔️','Recolor real do modelo de batalha.',45,'#75d8ff','#eaffff'),
('nefalem_common_2','nefalem','common','Verde Rift — Nefalem ⚔️','Recolor real do modelo de batalha.',45,'#86ffb0','#efffd5'),
('nefalem_common_3','nefalem','common','Rubro Solar — Nefalem ⚔️','Recolor real do modelo de batalha.',45,'#ff8fa3','#fff0b2'),
('nefalem_rare_1','nefalem','rare','Relicário — Nefalem ⚔️','Modelo raro único do personagem.',80,'#ffb8ff','#fff'),
('assault_epic_1','assault','epic','Armadura Solar','Exotraje de vanguarda solar com elmo, ombreiras e canhão próprios.',120,'#ffd166','#ff7a2f'),
('alchemist_epic_1','alchemist','epic','Cadinho Primordial','Armadura alquímica viva com máscara, tanques e catalisador próprios.',120,'#4ce0b3','#d9ff8e')
on conflict (skin_id) do update set character_key=excluded.character_key,rarity=excluded.rarity,name=excluded.name,description=excluded.description,cost=excluded.cost,color=excluded.color,accent=excluded.accent;

insert into public.chrono_mauro_augment_catalog(augment_id,character_key,name,icon,color,description,cost) values
('assault_arsenal','assault','Arsenal de um Perito','⚙️','#75d8ff','Tiros principais se dividem em 2 disparos menores ao atingir um alvo. Os disparos menores causam dano reduzido e não se dividem de novo.',170),
('assault_remorse','assault','Sem Remorsos','💣','#ff9c5a','Ao usar a chuva de granadas, cada granada tem 30% de chance de fragmentar ao cair, lançando 3 granadas menores laterais com dano reduzido.',170),
('sniper_execution','sniper','Linha de Execução','🎯','#ffd166','Disparos de precisão causam dano adicional contra inimigos feridos, aumentando conforme a vida atual do alvo estiver baixa.',170),
('sniper_still','sniper','Olho Imóvel','👁️','#ffe8a8','Quando o Sniper atira quase parado, o próximo disparo recebe um pulso concentrado de dano e deixa uma pequena linha de energia.',170),
('engineer_maintenance','engineer','Núcleo de Manutenção','✚','#62ff9b','Torretas e drones emitem pulsos verdes discretos de manutenção, fortalecendo a zona de controle do Artífice.',170),
('engineer_infernal','engineer','Torre Infernal Azul','🗼','#61dafb','Torretas recebem mais dano e ganham efeitos azuis mais agressivos, como uma torre infernal adaptada ao Chrono.',170),
('mage_condensed_void','mage','Vazio Condensado','🌌','#b58cff','Orbes e magias liberam mini pulsos de vazio ao acertar, causando dano em área pequena sem exagerar nos efeitos.',170),
('mage_between_doors','mage','Passos Entre Portas','🚪','#75d8ff','Teleportes deixam um eco dimensional no ponto de saída, ferindo e empurrando levemente inimigos próximos.',170),
('ronin_return_blade','ronin','Lâmina de Retorno','🗡️','#e8f2ff','Abates com o Ronin liberam cortes curtos ao redor do inimigo morto, ajudando a limpar grupos próximos.',170),
('ronin_oath','ronin','Juramento Imóvel','🛡️','#86ffb0','Depois do dash, o próximo impacto ofensivo recebe um brilho pesado de contra-ataque.',170),
('alchemist_volatile','alchemist','Química Instável','☣️','#b6ff7a','Venenos e poças químicas ficam mais perigosos, com pequenas bolhas tóxicas surgindo nos impactos.',170),
('alchemist_transmuter','alchemist','Transmutador de Guerra','⚗️','#4ce0b3','Habilidades do Alquimista têm chance de criar uma explosão química secundária no ponto mirado.',170),
('reaper_procession','reaper','Procissão das Almas','👻','#d7d7ff','Abates criam pequenas almas perseguidoras com visual limpo, que correm até outro inimigo e explodem em sombra.',170),
('reaper_eclipse','reaper','Ceifador do Eclipse','🌘','#ff7b9c','Habilidades do Reaper liberam um pulso sombrio que causa dano leve e reforça a presença tenebrosa do personagem.',170),
('colonel_ghost','colonel','Esquadrão Fantasma','🛩️','#9edfff','Ao usar habilidades pesadas, pequenas marcações de bombardeio aparecem em pontos diferentes do mapa, evitando concentrar tudo num alvo só.',170),
('colonel_command','colonel','Comando Blindado','🎖️','#ffd166','Explosões do Coronel criam ondas táticas curtas que atordoam por instantes os inimigos próximos.',170),
('bomber_napalm','bomber','Reator de Napalm','🔥','#ff8b5f','Explosões deixam pequenos focos de fogo no chão por alguns segundos, causando dano contínuo.',170),
('bomber_precision','bomber','Mina de Precisão','🧨','#ffd166','Algumas explosões soltam fragmentos laterais menores, úteis contra hordas sem virar bagunça visual.',170),
('archer_celestial_string','archer','Corda Celestial','🏹','#75d8ff','Flechas carregadas ganham um eco sônico curto, criando um risco luminoso após o acerto.',170),
('archer_judgement','archer','Flecha do Juízo','🌠','#ffd166','A Flecha Sônica Divina recebe uma onda extra de impacto ao ser usada, sem mudar a base do efeito que já está funcionando.',170),
('chrono_fractured_clock','chronoHero','Relógio Fraturado','⏱️','#9f6cff','Efeitos temporais deixam pequenos fragmentos de relógio no chão, causando lentidão e dano leve.',170),
('chrono_prism_core','chronoHero','Núcleo Prismático','💎','#75d8ff','Rajadas prismáticas recebem pulsos extras de energia, aumentando o impacto visual e o dano de área leve.',170),
('shadow_veil','shadowChild','Véu do Abismo','🕳️','#8f6bff','Facas abissais e venenos negros deixam rastros mais definidos e poças mais agressivas.',170),
('shadow_heir','shadowChild','Herdeiro do Fosso','😈','#ff304f','O Fosso Demoníaco fica mais brutal: suas ondas ganham dano adicional e um anel visual de ruptura.',170),
('moon_crescent','moonSlayer','Corte Lunar','🌙','#d7c4ff','Cortes dimensionais soltam pequenos crescentes que atravessam a linha de frente.',170),
('moon_sheath','moonSlayer','Bainha Astral','🗡️','#75d8ff','Ao carregar golpes especiais, o Exterminador recebe um escudo astral temporário.',170),
('rico_angle','ricocheteador','Ângulo Perfeito','◉','#ffd166','Bolas de impacto ganham mais precisão e podem soltar mini estilhaços após contatos fortes.',170),
('rico_table','ricocheteador','Mesa Impossível','🪞','#75d8ff','Refletores e tiros prismáticos recebem duração e impacto visual melhores.',170)
on conflict (augment_id) do update set character_key=excluded.character_key,name=excluded.name,icon=excluded.icon,color=excluded.color,description=excluded.description,cost=excluded.cost;

insert into public.chrono_mauro_relic_catalog(relic_id,name,description,cost) values
('glass_core','Núcleo de vidro','+20% dano global.',28),
('swift_circuit','Circuito Rápido','+14% velocidade.',28),
('focus_prism','Prisma de foco','+30 foco máximo.',29),
('armor_lattice','Malha de Armadura','+10% armadura.',30),
('drone_seed','Ajuda do Artífice','Começa com drone.',34),
('vampiric_core','Núcleo Vampírico','Kills curam 0,5% do HP máximo.',32),
('crit_matrix','Matrix Crítica','+15% chance crítico.',31),
('shield_cell','Célula de Escudo','+1 segmento de escudo máximo.',30),
('combo_amp','Amplificador de Escudo','Combo máximo +2 nível bônus.',33),
('eclipse_key','Chave das Relíquias','Bosses dropam +1 fragmento permanente.',35),
('magnet_heart','Coração Magnético','+70 alcance de coleta.',29),
('dash_servo','Servo do Dash','+35% recarga do dash.',31),
('hazard_suit','Roupa Antirradiação','-30% dano de hazards.',32),
('shop_contract','Cupom de Desconto','Itens da loja custam 12% menos.',32),
('turret_license','Licensa de Torretas','Torretas duram +40%.',30)
on conflict (relic_id) do update set name=excluded.name,description=excluded.description,cost=excluded.cost;

insert into public.chrono_mauro_power_catalog(power_id,name,rarity,description,weight) values
('dano_10','Dano +10%','COMUM','Aumenta todo dano causado em 10%.',42.0),
('cadencia_14','Cadência +14%','COMUM','Atira mais rápido. No Arqueiro também ajuda a carregar o tiro máximo.',37.0),
('velocidade_10','Velocidade +10%','COMUM','Melhora movimentação.',34.0),
('foco_18','Foco máximo +18','COMUM','Mais espaço para habilidades.',30.0),
('passos_leves','Passos Leves','COMUM','Aumenta velocidade e melhora levemente o dash.',24.0),
('foco_condensado','Foco Condensado','COMUM','Foco regenera melhor e habilidades ficam mais consistentes.',24.0),
('casca_temporal','Casca Temporal','COMUM','Ao tomar dano, ganha redução de dano por 2 segundos.',22.0),
('fragmento_magnetico','Fragmento Magnético','COMUM','Aumenta alcance de coleta de XP, ouro, relíquias e faíscas.',22.0),
('foco_5pct','Foco máximo +5%','COMUM','Aumenta o foco máximo em 5%.',25.0),
('hp_2pct','HP máximo +2%','COMUM','Aumenta o HP máximo em 2%.',25.0),
('perfuracao_1','Perfuração +1','RARO','Projéteis atravessam mais um inimigo.',20.0),
('critico_8','Crítico +8%','RARO','Mais chance de dano crítico.',18.0),
('tiro_fantasma','Tiro Fantasma','RARO','A cada alguns disparos, o próximo tiro atravessa paredes. Não afeta Bombardeiro nem Exterminador.',16.0),
('cacador_elite','Caçador de Elite','RARO','Causa mais dano contra elites, bosses e fissuras.',15.0),
('boost_distancia','Boost de Distância','RARO','Aumenta em 5% a distância do dash.',17.0),
('hp_5pct','HP máximo +5%','RARO','Aumenta o HP máximo em 5%.',17.0),
('passos_espinhosos','Passos Espinhosos','RARO','Aumenta o dano que o dash causa em 8%.',15.0),
('investimentos','Investimentos','RARO','Monstros dropam +5% de ouro.',15.0),
('cacador_tesouros','Caçador de Tesouros','RARO','Aumenta drops raros de bosses em 0.5%.',13.0),
('apressado','Apressado','RARO','Habilidades carregam 4% mais rápido.',14.0),
('balas_explosivas','Balas Explosivas','ÉPICO','Impactos causam explosões em área.',10.0),
('multishot_1','Multishot +1','ÉPICO','Adiciona um projétil extra por disparo.',9.0),
('armadura_10','Armadura +10%','ÉPICO','Reduz dano recebido.',8.0),
('acid_mastery','Acid Mastery','ÉPICO','Venenos ficam 35% mais fortes.',7.0),
('nucleo_reativo','Núcleo Reativo','ÉPICO','Único: quando o escudo quebra por completo, explode em volta. Cooldown de 5s.',7.0),
('sangue_cronal','Sangue Cronal','ÉPICO','Kills têm chance de acelerar regeneração de escudo e recuperar um pouco de HP.',7.0),
('lifesteal_05','Lifesteal +0.5%','ÉPICO','Cura uma pequena parte do dano causado.',7.0),
('drone_aliado','Drone Aliado','ÉPICO','Adiciona um drone aliado automático. Máximo de 4 drones, contando o drone da relíquia.',8.0),
('forca_descomunal','Força Descomunal','ÉPICO','Aumenta o dano em 15% e HP em 10%.',7.0),
('precisao_cirurgica','Precisão Cirúrgica','ÉPICO','Aumenta sua chance crítica e dano geral, mas reduz o foco máximo em 10%.',7.0),
('cacador_mestre_tesouros','Caçador Mestre de Tesouros','ÉPICO','Aumenta drops raros de bosses em 1.5%.',6.0),
('investidor_nato','Investidor Nato','ÉPICO','Monstros dropam +10% de ouro.',6.0),
('sem_tempo_conversas','Sem Tempo pra Conversas','ÉPICO','Habilidades e dash carregam 8% mais rápido.',6.0),
('rei_financas','Rei das Finanças','LENDÁRIO','Monstros dropam +20% de ouro e +5% de relíquias.',2.2),
('mini_torreta_permanente','Mini-Torreta Permanente','LENDÁRIO','Adiciona uma mini-torreta permanente à arena. Pode aparecer até 4 vezes.',2.0),
('bencao_chronos','Benção dos Chronos','LENDÁRIO','Chance de ao invés de tomar dano, recuperar 5% de HP.',1.7),
('drop_vampirico','Drop Vampírico','LENDÁRIO','Chance de inimigos deixarem kits médicos no chão ao morrerem.',1.6),
('cadaver_flamejante','Cadáver Flamejante','LENDÁRIO','Chance de queimar o chão com o corpo de seus inimigos.',1.45),
('cadaver_congelante','Cadáver Congelante','LENDÁRIO','Chance de congelar o chão com o corpo de seus inimigos.',1.45),
('orbita_desaceleradora','Órbita Desaceleradora','LENDÁRIO','Cria uma órbita que aparece e desaparece, desacelerando tiros inimigos próximos.',1.3),
('rei_piratas','Rei dos Piratas','LENDÁRIO','Aumenta drops raros de bosses em 5% e bosses dropam +10% de relíquias.',1.25),
('sai_pra_la','Sai Pra Lá!','LENDÁRIO','O dash vai dar um empurrão nos inimigos deixando eles paralisados por um tempo.',1.25),
('necromante_elementar','Necromante Elementar','MÍTICO','Chance de transformar inimigos em aliados elementais. +35% dano, +50% foco, +25% HP, -35% cadência.',0.01),
('unidade_suprema','Unidade Suprema','MÍTICO','+50% velocidade, +100% cadência, +5 projéteis, +100% HP máximo e +25% dano.',0.01)
on conflict (power_id) do update set name=excluded.name,rarity=excluded.rarity,description=excluded.description,weight=excluded.weight;

insert into public.chrono_bestiary_catalog(entry_id,tab,group_name,name,required_kills,relic_reward) values
('chaser','general','Comuns','Chaser',30,3),
('strafer','general','Comuns','Strafer',30,3),
('tank','general','Comuns','Tank',30,3),
('bomber','general','Comuns','Bomber',30,3),
('swarmer','general','Comuns','Swarmer',30,3),
('sentinel','general','Comuns','Sentinel',30,3),
('leaper','general','Comuns','Leaper',30,3),
('medic','general','Elites','Medic Drone',20,12),
('sniperDrone','general','Elites','Sniper Drone',20,12),
('splitter','general','Elites','Splitter',20,12),
('vomiter','general','Elites','Vomiter',30,3),
('pukeling','general','Elites','Pukeling',20,12),
('dreadbus','general','Elites','Carcaça-Crisálida',15,5),
('nullHerald','general','Elites','Arauto do Zero',15,5),
('riftTick','general','Comuns','Carrapato Cronal',30,3),
('glassMantis','general','Comuns','Louva-Vidro',30,3),
('phaseLurker','general','Comuns','Escavador de Fase',30,3),
('glassCrawler','general','Elites','Rastejante de Vidro',20,12),
('manaParasite','general','Elites','Parasita de Mana',20,12),
('stoneColossus','general','Elites','Colosso de Pedra Viva',20,12),
('voidWeaver','general','Elites','Tecelão do Vazio',20,12),
('chronoMosquito','rift','Elites','Mosquito Cronal',20,12),
('ruinCharger','rift','Elites','Carregador da Ruína',20,12),
('towerEater','rift','Elites','Engolidor de Torres',20,12),
('riftHerald','rift','Elites','Arauto das Fendas',20,12),
('coreDevourer','rift','Bosses','Devoradora de Núcleos',1,25),
('archon','general','Bosses','Archon Core',2,15),
('titan','general','Bosses','Titan Bastion',2,15),
('oracle','general','Bosses','Oracle Bloom',2,15),
('eclipseInquisitor','general','Bosses','Inquisidor do Eclipse',2,15),
('glacialBeast','general','Bosses','Besta Gélida de Chrono',2,15),
('lostEmperor','general','???','Emperador Perdido',1,50),
('doomPortal800','doom','Estruturas','Portal Infernal',5,12),
('doomTotem800','doom','Estruturas','Totem do DOOM',5,12),
('doomMini_butcher800','doom','Minibosses','Doom Butcher',5,12),
('doomMini_priest800','doom','Minibosses','Hell Priest',5,12),
('doomMini_harvester800','doom','Minibosses','The Harvester',5,12),
('doomMini_carrier800','doom','Minibosses','Doom Carrier',5,12),
('infernalImp810','doom','Lacaios','Servo do Abismo',5,12),
('infernalBoss810','doom','Bosses','Devorador Infernal',2,25)
on conflict (entry_id) do update set tab=excluded.tab,group_name=excluded.group_name,name=excluded.name,required_kills=excluded.required_kills,relic_reward=excluded.relic_reward;

create or replace function public.chrono_seed_mod_server(p_seed text, p_mod integer)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case when p_mod <= 0 then 0 else ((hashtextextended(p_seed, 0) & 9223372036854775807) % p_mod)::integer end;
$$;

create or replace function public.chrono_rarity_rank_server(p_rarity text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_rarity when 'common' then 0 when 'rare' then 1 when 'epic' then 2 when 'legendary' then 3 when 'mythic' then 4 else 0 end;
$$;

create or replace function public.chrono_chest_roll_rarity_server(p_seed text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare v_roll integer := public.chrono_seed_mod_server(p_seed, 10000);
begin
  if v_roll < 100 then return 'mythic'; end if;
  if v_roll < 450 then return 'legendary'; end if;
  if v_roll < 1950 then return 'epic'; end if;
  if v_roll < 4950 then return 'rare'; end if;
  return 'common';
end;
$$;

create or replace function public.chrono_build_mauro_rotation_server(p_user_id uuid, p_epoch bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.chrono_player_inventory%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_qty integer;
  v_aug1 public.chrono_mauro_augment_catalog%rowtype;
  v_aug2 public.chrono_mauro_augment_catalog%rowtype;
  v_skin1 public.chrono_mauro_skin_catalog%rowtype;
  v_skin2 public.chrono_mauro_skin_catalog%rowtype;
  v_skin3 public.chrono_mauro_skin_catalog%rowtype;
  v_skin4 public.chrono_mauro_skin_catalog%rowtype;
  v_chest boolean;
  v_roll integer;
  v_level text;
  v_cost bigint;
  v_attempts integer;
  v_start text;
  v_item jsonb;
begin
  insert into public.chrono_player_inventory(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_inv from public.chrono_player_inventory where user_id=p_user_id;

  v_roll := public.chrono_seed_mod_server(p_user_id::text||':'||p_epoch||':keys',100);
  v_qty := case when v_roll<60 then 1 when v_roll<80 then 2 when v_roll<90 then 3 when v_roll<97 then 4 else 5 end;
  v_cost := case v_qty when 1 then 70 when 2 then 105 when 3 then 140 when 4 then 170 else 195 end;
  v_items := v_items || jsonb_build_array(jsonb_build_object('type','key','icon','🗝️','title',v_qty||case when v_qty=1 then ' Chave de Awakening' else ' Chaves de Awakening' end,'qty',v_qty,'cost',v_cost,'color','#ffd166','desc','Chaves para liberar missões de Awakening.'));

  v_roll := public.chrono_seed_mod_server(p_user_id::text||':'||p_epoch||':chrono',100);
  v_qty := case when v_roll<80 then 1 when v_roll<95 then 2 else 3 end;
  v_cost := case v_qty when 1 then 120 when 2 then 190 else 260 end;
  v_items := v_items || jsonb_build_array(jsonb_build_object('type','chrono','icon','✦','title',v_qty||case when v_qty=1 then ' Fragmento Chrono' else ' Fragmentos Chrono' end,'qty',v_qty,'cost',v_cost,'color','#9f6cff','desc','Fragmentos raros para upgrades finais.'));

  select * into v_aug1 from public.chrono_mauro_augment_catalog a
  where not (a.augment_id = any(v_inv.augments))
  order by md5(p_user_id::text||':'||p_epoch||':aug1:'||a.augment_id) limit 1;
  if v_aug1.augment_id is null then
    v_items := v_items || jsonb_build_array(jsonb_build_object('type','empty','icon','⧖','title','Ampliação indisponível','cost',0,'color','#8a8a9b','desc','Nenhuma Ampliação nova disponível.'));
  else
    v_items := v_items || jsonb_build_array(jsonb_build_object('type','aug','icon',v_aug1.icon,'title',v_aug1.name,'augId',v_aug1.augment_id,'classKey',v_aug1.character_key,'cost',v_aug1.cost,'color',v_aug1.color,'desc','Ampliação Chronal de personagem.'));
  end if;

  v_chest := public.chrono_seed_mod_server(p_user_id::text||':'||p_epoch||':slot3',2)=0;
  if v_chest then
    v_roll := public.chrono_seed_mod_server(p_user_id::text||':'||p_epoch||':chest-level',100);
    if v_roll<80 then v_level:='common';v_cost:=50;v_attempts:=5;v_start:='common';
    elsif v_roll<97 then v_level:='rare';v_cost:=75;v_attempts:=3;v_start:='rare';
    else v_level:='epic';v_cost:=120;v_attempts:=3;v_start:='epic'; end if;
    v_items := v_items || jsonb_build_array(jsonb_build_object('type','mauroChest714','icon',case v_level when 'common' then '🧰' when 'rare' then '🟩' else '🟪' end,'title','Baú Chronal '||case v_level when 'common' then 'Comum' when 'rare' then 'Raro' else 'Épico' end,'chestLevel',v_level,'startRarity',v_start,'attempts',v_attempts,'cost',v_cost,'color',case v_level when 'common' then '#86a2bd' when 'rare' then '#4ce0b3' else '#b77cff' end,'desc','Baú especial com três recompensas calculadas pelo servidor.'));
  else
    select * into v_aug2 from public.chrono_mauro_augment_catalog a
    where not (a.augment_id = any(v_inv.augments)) and a.augment_id is distinct from v_aug1.augment_id
    order by md5(p_user_id::text||':'||p_epoch||':aug2:'||a.augment_id) limit 1;
    if v_aug2.augment_id is null then
      v_items := v_items || jsonb_build_array(jsonb_build_object('type','empty','icon','⧖','title','Ampliação indisponível','cost',0,'color','#8a8a9b','desc','Nenhuma Ampliação nova disponível.'));
    else
      v_items := v_items || jsonb_build_array(jsonb_build_object('type','aug','icon',v_aug2.icon,'title',v_aug2.name,'augId',v_aug2.augment_id,'classKey',v_aug2.character_key,'cost',v_aug2.cost,'color',v_aug2.color,'desc','Ampliação Chronal de personagem.'));
    end if;
  end if;

  select * into v_skin1 from public.chrono_mauro_skin_catalog s where s.rarity='common' and not(s.skin_id=any(v_inv.skins)) order by md5(p_user_id::text||':'||p_epoch||':skin4:'||s.skin_id) limit 1;
  select * into v_skin2 from public.chrono_mauro_skin_catalog s where s.rarity='common' and not(s.skin_id=any(v_inv.skins)) and s.skin_id is distinct from v_skin1.skin_id order by md5(p_user_id::text||':'||p_epoch||':skin5:'||s.skin_id) limit 1;
  select * into v_skin3 from public.chrono_mauro_skin_catalog s where s.rarity='rare' and not(s.skin_id=any(v_inv.skins)) order by md5(p_user_id::text||':'||p_epoch||':skin6:'||s.skin_id) limit 1;
  select * into v_skin4 from public.chrono_mauro_skin_catalog s where s.rarity='epic' and not(s.skin_id=any(v_inv.skins)) order by md5(p_user_id::text||':'||p_epoch||':skin7:'||s.skin_id) limit 1;

  foreach v_item in array array[
    case when v_skin1.skin_id is null then jsonb_build_object('type','empty','icon','👕','title','Skin indisponível','cost',0,'color','#8a8a9b','desc','Nenhuma skin comum nova disponível.') else jsonb_build_object('type','skin','icon','👕','title',v_skin1.name,'skinId',v_skin1.skin_id,'classKey',v_skin1.character_key,'rarity',v_skin1.rarity,'cost',v_skin1.cost,'color',v_skin1.color,'desc','Skin comum para personagem.') end,
    case when v_skin2.skin_id is null then jsonb_build_object('type','empty','icon','👕','title','Skin indisponível','cost',0,'color','#8a8a9b','desc','Nenhuma skin comum nova disponível.') else jsonb_build_object('type','skin','icon','👕','title',v_skin2.name,'skinId',v_skin2.skin_id,'classKey',v_skin2.character_key,'rarity',v_skin2.rarity,'cost',v_skin2.cost,'color',v_skin2.color,'desc','Skin comum para personagem.') end,
    case when v_skin3.skin_id is null then jsonb_build_object('type','empty','icon','👕','title','Skin indisponível','cost',0,'color','#8a8a9b','desc','Nenhuma skin rara nova disponível.') else jsonb_build_object('type','skin','icon','👕','title',v_skin3.name,'skinId',v_skin3.skin_id,'classKey',v_skin3.character_key,'rarity',v_skin3.rarity,'cost',v_skin3.cost,'color',v_skin3.color,'desc','Skin rara para personagem.') end,
    case when v_skin4.skin_id is null then jsonb_build_object('type','empty','icon','👕','title','Skin indisponível','cost',0,'color','#8a8a9b','desc','Nenhuma skin épica nova disponível.') else jsonb_build_object('type','skin','icon','👕','title',v_skin4.name,'skinId',v_skin4.skin_id,'classKey',v_skin4.character_key,'rarity',v_skin4.rarity,'cost',v_skin4.cost,'color',v_skin4.color,'desc','Skin épica para personagem.') end
  ] loop
    v_items := v_items || jsonb_build_array(v_item);
  end loop;
  return v_items;
end;
$$;

create or replace function public.chrono_refresh_mauro_locked_server(p_user_id uuid)
returns public.chrono_player_mauro
language plpgsql
security definer
set search_path = ''
as $$
declare v_row public.chrono_player_mauro%rowtype; v_epoch bigint;
begin
  insert into public.chrono_player_inventory(user_id) values(p_user_id) on conflict(user_id) do nothing;
  insert into public.chrono_player_mauro(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_row from public.chrono_player_mauro where user_id=p_user_id for update;
  v_epoch := floor(extract(epoch from clock_timestamp())/600)::bigint;
  if v_row.rotation_epoch<>v_epoch or jsonb_array_length(v_row.rotation_items)<>8 then
    update public.chrono_player_mauro set rotation_epoch=v_epoch,rotation_items=public.chrono_build_mauro_rotation_server(p_user_id,v_epoch),sold_slots='{}'::jsonb,updated_at=now() where user_id=p_user_id returning * into v_row;
  end if;
  return v_row;
end;
$$;

create or replace function public.chrono_mauro_bestiary_payload_server(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_inv public.chrono_player_inventory%rowtype;
  v_mauro public.chrono_player_mauro%rowtype;
  v_inf public.chrono_player_infernal%rowtype;
  v_entries jsonb;
  v_defaults text[];
  v_all_skins text[];
  v_all_augments text[];
  v_selected jsonb := '{}'::jsonb;
  v_pair record;
begin
  insert into public.chrono_player_state(user_id) values(p_user_id) on conflict(user_id) do nothing;
  insert into public.chrono_player_inventory(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_state from public.chrono_player_state where user_id=p_user_id;
  select * into v_inv from public.chrono_player_inventory where user_id=p_user_id;
  insert into public.chrono_player_infernal(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_inf from public.chrono_player_infernal where user_id=p_user_id;
  v_mauro := public.chrono_refresh_mauro_locked_server(p_user_id);
  select coalesce(array_agg(skin_id order by skin_id),'{}'::text[]) into v_defaults from public.chrono_mauro_skin_catalog where rarity='base';
  select coalesce(array_agg(distinct x order by x),'{}'::text[]) into v_all_skins from unnest(v_defaults||v_inv.skins||coalesce(v_inf.demon_skins,'{}'::text[])) x;
  select coalesce(array_agg(distinct x order by x),'{}'::text[]) into v_all_augments from unnest(v_inv.augments||coalesce(v_inf.infernal_augments,'{}'::text[])) x;

  -- Limpa seleções antigas ou manipuladas. O payload nunca anuncia como equipada
  -- uma skin que não pertence à conta ou que pertence a outro personagem.
  for v_pair in select key,value from jsonb_each_text(coalesce(v_inv.selected_skins,'{}'::jsonb)) loop
    if exists(
      select 1 from public.chrono_mauro_skin_catalog s
      where s.skin_id=v_pair.value and s.character_key=v_pair.key
        and (s.rarity='base' or s.skin_id=any(v_inv.skins))
    ) or (
      v_pair.value=any(coalesce(v_inf.demon_skins,'{}'::text[]))
      and (v_pair.value like ('demon_'||v_pair.key||'_%') or (v_pair.key='ricocheteador' and v_pair.value like 'demon_rico_%'))
    ) then
      v_selected:=jsonb_set(v_selected,array[v_pair.key],to_jsonb(v_pair.value),true);
    end if;
  end loop;
  if v_selected<>v_inv.selected_skins then
    update public.chrono_player_inventory set selected_skins=v_selected,updated_at=now() where user_id=p_user_id;
    v_inv.selected_skins:=v_selected;
  end if;

  select coalesce(jsonb_object_agg(c.entry_id,jsonb_build_object('kills',coalesce(p.kills,0),'claimed',p.claimed_at is not null,'ready',coalesce(p.kills,0)>=c.required_kills and p.claimed_at is null,'required',c.required_kills,'reward',c.relic_reward)),'{}'::jsonb)
  into v_entries from public.chrono_bestiary_catalog c left join public.chrono_player_bestiary p on p.user_id=p_user_id and p.entry_id=c.entry_id;
  return jsonb_build_object(
    'serverTime',floor(extract(epoch from clock_timestamp())*1000),'revision',v_state.revision,
    'wallet',jsonb_build_object('relics',v_state.relic_shards,'chrono',v_state.chrono_fragments,'keys',v_state.awakening_keys),
    'mauro',jsonb_build_object('authority',true,'shop',jsonb_build_object('version',3,'created',v_mauro.rotation_epoch*600000,'next',(v_mauro.rotation_epoch+1)*600000,'rotationId',p_user_id::text||':'||v_mauro.rotation_epoch,'items',v_mauro.rotation_items,'sold',v_mauro.sold_slots,'priceBoost703',true,'chestSlot714',(v_mauro.rotation_epoch*600000)::text||'_'||((v_mauro.rotation_epoch+1)*600000)::text,'chestSlotKind714',case when v_mauro.rotation_items->3->>'type'='mauroChest714' then 'chest' else 'augmentation' end,'serverAuthority870',true),'inventory',jsonb_build_object('skins',to_jsonb(v_all_skins),'augments',to_jsonb(v_all_augments),'permanentRelics',to_jsonb(v_inv.permanent_relics),'catalogPowerups',to_jsonb(v_inv.catalog_powerups),'selectedSkins',v_selected),'permanent',(select coalesce(jsonb_agg(jsonb_build_object('id',r.relic_id,'name',r.name,'desc',r.description,'cost',r.cost) order by r.cost,r.relic_id),'[]'::jsonb) from public.chrono_mauro_relic_catalog r)),
    'bestiary',jsonb_build_object('authority',true,'entries',v_entries)
  );
end;
$$;

create or replace function public.chrono_mauro_purchase_server(
  p_user_id uuid,p_request_id uuid,p_section text,p_rotation_id text default '',p_slot integer default -1,p_item_key text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous jsonb; v_state public.chrono_player_state%rowtype; v_inv public.chrono_player_inventory%rowtype; v_mauro public.chrono_player_mauro%rowtype;
  v_item jsonb; v_cost bigint; v_type text; v_payload jsonb; v_response jsonb; v_sold jsonb; v_key text;
  v_start text; v_final text; v_roll_rarity text; v_attempts integer; v_rolls jsonb:='[]'::jsonb; v_rewards jsonb:='[]'::jsonb;
  v_before text; v_i integer; v_roll integer; v_reward_type text; v_amount integer; v_aug public.chrono_mauro_augment_catalog%rowtype; v_power public.chrono_mauro_power_catalog%rowtype;
  v_meta jsonb; v_save jsonb; v_rare boolean; v_seed text;
begin
  -- Serializa retries concorrentes do mesmo request_id antes de consultar o recibo.
  perform pg_advisory_xact_lock(hashtextextended('chrono:mauro:'||p_user_id::text||':'||p_request_id::text,0));
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;
  if found then return v_previous; end if;
  select * into v_state from public.chrono_player_state where user_id=p_user_id for update;
  if not found or not v_state.initialized then raise exception 'Save online não inicializado'; end if;
  if not v_state.mauro_authority_enabled then raise exception 'Loja do Mauro ainda não está autoritativa'; end if;
  insert into public.chrono_player_inventory(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_inv from public.chrono_player_inventory where user_id=p_user_id for update;

  if p_section='permanent' then
    select relic_id,name,description,cost into v_key,v_type,v_start,v_cost from public.chrono_mauro_relic_catalog where relic_id=p_item_key;
    if not found then raise exception 'Power-up permanente inválido'; end if;
    if v_key=any(v_inv.permanent_relics) then raise exception 'Power-up permanente já adquirido'; end if;
    if v_state.relic_shards<v_cost then raise exception 'Relíquias insuficientes'; end if;
    v_state.relic_shards:=v_state.relic_shards-v_cost; v_inv.permanent_relics:=array_append(v_inv.permanent_relics,v_key);
    update public.chrono_player_inventory set permanent_relics=v_inv.permanent_relics,updated_at=now() where user_id=p_user_id;
    update public.chrono_player_state set relic_shards=v_state.relic_shards,revision=revision+1 where user_id=p_user_id returning * into v_state;
    v_payload:=public.chrono_mauro_bestiary_payload_server(p_user_id);
    v_response:=jsonb_build_object('purchase',jsonb_build_object('section','permanent','itemId',v_key,'title',v_type,'cost',v_cost),'payload',v_payload);
  elsif p_section='rotation' then
    if p_slot<0 or p_slot>7 then raise exception 'Slot da Loja do Mauro inválido'; end if;
    v_mauro:=public.chrono_refresh_mauro_locked_server(p_user_id);
    if p_rotation_id<>(p_user_id::text||':'||v_mauro.rotation_epoch::text) then raise exception 'A rotação da Loja do Mauro venceu'; end if;
    if coalesce((v_mauro.sold_slots->>p_slot::text)::boolean,false) then raise exception 'Item esgotado nesta rotação'; end if;
    v_item:=v_mauro.rotation_items->p_slot; v_type:=coalesce(v_item->>'type',''); v_cost:=coalesce((v_item->>'cost')::bigint,0);
    if v_type='' or v_type='empty' then raise exception 'Item indisponível'; end if;
    if v_state.relic_shards<v_cost then raise exception 'Relíquias insuficientes'; end if;
    if v_type='aug' and (v_item->>'augId')=any(v_inv.augments) then raise exception 'Ampliação já adquirida'; end if;
    if v_type='skin' and (v_item->>'skinId')=any(v_inv.skins) then raise exception 'Skin já adquirida'; end if;
    v_state.relic_shards:=v_state.relic_shards-v_cost;
    if v_type='key' then v_state.awakening_keys:=v_state.awakening_keys+coalesce((v_item->>'qty')::integer,0);
    elsif v_type='chrono' then v_state.chrono_fragments:=v_state.chrono_fragments+coalesce((v_item->>'qty')::integer,0);
    elsif v_type='aug' then v_inv.augments:=array_append(v_inv.augments,v_item->>'augId');
    elsif v_type='skin' then v_inv.skins:=array_append(v_inv.skins,v_item->>'skinId');
    elsif v_type='mauroChest714' then
      -- O request_id garante idempotência, mas não participa sozinho do sorteio:
      -- o nonce criptográfico do servidor impede que o cliente procure UUIDs favoráveis.
      v_seed:=encode(gen_random_bytes(32),'hex')||':'||p_user_id::text||':'||p_request_id::text;
      v_start:=coalesce(v_item->>'startRarity','common'); v_final:=v_start; v_attempts:=coalesce((v_item->>'attempts')::integer,case when v_start='common' then 5 else 3 end);
      for v_i in 1..v_attempts loop
        v_before:=v_final; v_roll_rarity:=public.chrono_chest_roll_rarity_server(v_seed||':rarity:'||v_i);
        if public.chrono_rarity_rank_server(v_roll_rarity)>public.chrono_rarity_rank_server(v_final) then v_final:=v_roll_rarity; end if;
        v_rolls:=v_rolls||jsonb_build_array(jsonb_build_object('attempt',v_i,'rolled',v_roll_rarity,'before',v_before,'after',v_final,'upgraded',v_before<>v_final));
        exit when v_final='mythic';
      end loop;
      for v_i in 1..3 loop
        v_roll:=public.chrono_seed_mod_server(v_seed||':reward-type:'||v_i,1000);
        if v_final='common' then v_reward_type:=case when v_roll<700 then 'relic' when v_roll<850 then 'augment' else 'power' end;
        elsif v_final='rare' then v_reward_type:=case when v_roll<500 then 'relic' when v_roll<650 then 'key' when v_roll<800 then 'augment' else 'power' end;
        elsif v_final='epic' then v_reward_type:=case when v_roll<350 then 'relic' when v_roll<550 then 'key' when v_roll<700 then 'chrono' when v_roll<850 then 'augment' else 'power' end;
        elsif v_final='legendary' then v_reward_type:=case when v_roll<250 then 'relic' when v_roll<450 then 'key' when v_roll<650 then 'chrono' when v_roll<800 then 'augment' else 'power' end;
        else v_reward_type:=case when v_roll<200 then 'relic' when v_roll<400 then 'key' when v_roll<600 then 'chrono' when v_roll<780 then 'augment' when v_roll<995 then 'power' else 'secret' end; end if;
        v_rare:=v_final in ('legendary','mythic');
        if v_reward_type='relic' then
          v_amount:=case v_final when 'common' then 1+public.chrono_seed_mod_server(v_seed||':relic:'||v_i,3) when 'rare' then 3+public.chrono_seed_mod_server(v_seed||':relic:'||v_i,3) when 'epic' then 4+public.chrono_seed_mod_server(v_seed||':relic:'||v_i,7) when 'legendary' then 11+public.chrono_seed_mod_server(v_seed||':relic:'||v_i,15) else 35+public.chrono_seed_mod_server(v_seed||':relic:'||v_i,26) end;
          v_state.relic_shards:=v_state.relic_shards+v_amount; v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','🜂','title','+'||v_amount||' relíquias','desc','Progresso permanente recebido.','kind','relic','rare',v_rare));
        elsif v_reward_type='key' then
          v_amount:=case v_final when 'rare' then 1 when 'epic' then 2+public.chrono_seed_mod_server(v_seed||':key:'||v_i,2) when 'legendary' then 3+public.chrono_seed_mod_server(v_seed||':key:'||v_i,2) else 4+public.chrono_seed_mod_server(v_seed||':key:'||v_i,5) end;
          v_state.awakening_keys:=v_state.awakening_keys+v_amount; v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','🗝️','title','+'||v_amount||case when v_amount=1 then ' chave de Awakening' else ' chaves de Awakening' end,'desc','Usada nas jornadas de Awakening.','kind','key','rare',v_rare));
        elsif v_reward_type='chrono' then
          v_amount:=case v_final when 'epic' then 1 when 'legendary' then 2+public.chrono_seed_mod_server(v_seed||':chrono:'||v_i,3) else 5+public.chrono_seed_mod_server(v_seed||':chrono:'||v_i,6) end;
          v_state.chrono_fragments:=v_state.chrono_fragments+v_amount; v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','✦','title','+'||v_amount||case when v_amount=1 then ' Fragmento Chrono' else ' Fragmentos Chrono' end,'desc','Recurso raro da progressão.','kind','chrono','rare',true));
        elsif v_reward_type='augment' then
          select * into v_aug from public.chrono_mauro_augment_catalog a where not(a.augment_id=any(v_inv.augments)) order by md5(v_seed||':augment:'||v_i||':'||a.augment_id) limit 1;
          if v_aug.augment_id is null then
            v_amount:=case when v_final='mythic' then 20 else 8 end; v_state.relic_shards:=v_state.relic_shards+v_amount; v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','🜂','title','+'||v_amount||' relíquias','desc','Todas as Ampliações já pertencem à conta.','kind','relic','rare',v_rare));
          else
            v_inv.augments:=array_append(v_inv.augments,v_aug.augment_id); v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon',v_aug.icon,'title',v_aug.name,'desc','Ampliação Chronal adicionada ao inventário.','kind','augmentation','itemId',v_aug.augment_id,'rare',true,'color',v_aug.color));
          end if;
        elsif v_reward_type='power' then
          select * into v_power from public.chrono_mauro_power_catalog p where not(p.power_id=any(v_inv.catalog_powerups)) and p.rarity=case v_final when 'common' then 'RARO' when 'rare' then 'RARO' when 'epic' then 'ÉPICO' when 'legendary' then 'LENDÁRIO' else 'MÍTICO' end order by md5(v_seed||':power:'||v_i||':'||p.power_id) limit 1;
          if v_power.power_id is null then
            select * into v_power from public.chrono_mauro_power_catalog p where not(p.power_id=any(v_inv.catalog_powerups)) order by md5(v_seed||':power-fallback:'||v_i||':'||p.power_id) limit 1;
          end if;
          if v_power.power_id is null then
            v_amount:=case when v_final='mythic' then 20 else 8 end;v_state.relic_shards:=v_state.relic_shards+v_amount;v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','🜂','title','+'||v_amount||' relíquias','desc','Catálogo de poderes já completo.','kind','relic','rare',v_rare));
          else
            v_inv.catalog_powerups:=array_append(v_inv.catalog_powerups,v_power.power_id);v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','✨','title',v_power.name,'desc',v_power.description,'kind','power','itemId',v_power.power_id,'rare',v_power.rarity in ('LENDÁRIO','MÍTICO')));
          end if;
        else
          v_save:=coalesce(v_state.save_data,'{}'::jsonb);v_meta:=coalesce(v_save->'chrono_v4_meta','{}'::jsonb);
          if public.chrono_safe_bool_server(v_meta->>'stellarEmperorRevealed') or public.chrono_safe_bool_server(v_meta->>'stellarEmperorSecretUnlocked') then
            v_amount:=20;v_state.chrono_fragments:=v_state.chrono_fragments+v_amount;
            v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','✦','title','+20 Fragmentos Chrono','desc','O segredo do Emperador Estelar já estava revelado.','kind','chrono','rare',true));
          else
            v_meta:=jsonb_set(jsonb_set(v_meta,'{stellarEmperorRevealed}','true'::jsonb,true),'{stellarEmperorSecretUnlocked}','true'::jsonb,true);v_save:=jsonb_set(v_save,'{chrono_v4_meta}',v_meta,true);v_state.save_data:=v_save;
            v_rewards:=v_rewards||jsonb_build_array(jsonb_build_object('icon','🌟','title','Emperador Estelar revelado','desc','O personagem apareceu para compra por Fragmentos Chrono.','kind','secret','rare',true));
          end if;
        end if;
      end loop;
    end if;
    update public.chrono_player_inventory set skins=(select coalesce(array_agg(distinct x),'{}'::text[]) from unnest(v_inv.skins) x),augments=(select coalesce(array_agg(distinct x),'{}'::text[]) from unnest(v_inv.augments) x),catalog_powerups=(select coalesce(array_agg(distinct x),'{}'::text[]) from unnest(v_inv.catalog_powerups) x),updated_at=now() where user_id=p_user_id;
    update public.chrono_player_state set relic_shards=v_state.relic_shards,chrono_fragments=v_state.chrono_fragments,awakening_keys=v_state.awakening_keys,save_data=coalesce(v_state.save_data,save_data),revision=revision+1 where user_id=p_user_id returning * into v_state;
    v_sold:=jsonb_set(v_mauro.sold_slots,array[p_slot::text],'true'::jsonb,true);update public.chrono_player_mauro set sold_slots=v_sold,updated_at=now() where user_id=p_user_id;
    v_payload:=public.chrono_mauro_bestiary_payload_server(p_user_id);
    v_response:=jsonb_build_object('purchase',jsonb_build_object('section','rotation','slot',p_slot,'type',v_type,'cost',v_cost,'item',v_item),'chest',case when v_type='mauroChest714' then jsonb_build_object('startRarity',v_start,'finalRarity',v_final,'rolls',v_rolls,'rewards',v_rewards) else 'null'::jsonb end,'payload',v_payload);
  else raise exception 'Seção da Loja do Mauro inválida'; end if;
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'mauro_purchase',v_response);
  return v_response;
end;
$$;

create or replace function public.chrono_mauro_equip_skin_server(p_user_id uuid,p_request_id uuid,p_character_key text,p_skin_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_previous jsonb;v_inv public.chrono_player_inventory%rowtype;v_inf public.chrono_player_infernal%rowtype;v_skin public.chrono_mauro_skin_catalog%rowtype;v_response jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('chrono:mauro-skin:'||p_user_id::text||':'||p_request_id::text,0));
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;if found then return v_previous;end if;
  insert into public.chrono_player_inventory(user_id) values(p_user_id) on conflict(user_id) do nothing;
  insert into public.chrono_player_infernal(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_inv from public.chrono_player_inventory where user_id=p_user_id for update;select * into v_inf from public.chrono_player_infernal where user_id=p_user_id;
  select * into v_skin from public.chrono_mauro_skin_catalog where skin_id=p_skin_id and character_key=p_character_key;
  if v_skin.skin_id is null and not(p_skin_id=any(coalesce(v_inf.demon_skins,'{}'::text[]))) then raise exception 'Skin inválida para este personagem';end if;
  if p_skin_id=any(coalesce(v_inf.demon_skins,'{}'::text[])) and not(p_skin_id like ('demon_'||p_character_key||'_%') or (p_character_key='ricocheteador' and p_skin_id like 'demon_rico_%')) then raise exception 'Skin demoníaca pertence a outro personagem';end if;
  if not(coalesce(v_skin.rarity,'')='base' or p_skin_id=any(v_inv.skins) or p_skin_id=any(coalesce(v_inf.demon_skins,'{}'::text[]))) then raise exception 'Skin não adquirida';end if;
  v_inv.selected_skins:=jsonb_set(v_inv.selected_skins,array[p_character_key],to_jsonb(p_skin_id),true);update public.chrono_player_inventory set selected_skins=v_inv.selected_skins,updated_at=now() where user_id=p_user_id;update public.chrono_player_state set revision=revision+1 where user_id=p_user_id;
  v_response:=jsonb_build_object('equipped',true,'characterKey',p_character_key,'skinId',p_skin_id,'payload',public.chrono_mauro_bestiary_payload_server(p_user_id));insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'mauro_equip_skin',v_response);return v_response;
end;$$;

create or replace function public.chrono_apply_bestiary_run_server(p_user_id uuid,p_session_id uuid,p_total_kills bigint,p_type_kills jsonb,p_final boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_session public.chrono_game_sessions%rowtype;v_counter public.chrono_bestiary_run_counters%rowtype;v_state public.chrono_player_state%rowtype;v_pair record;v_value bigint;v_prev bigint;v_delta bigint;v_sum bigint:=0;v_official_total bigint:=0;v_updated jsonb:='{}'::jsonb;
begin
  if p_total_kills<0 or jsonb_typeof(coalesce(p_type_kills,'{}'::jsonb))<>'object' then raise exception 'Resumo do Bestiário inválido';end if;
  select * into v_state from public.chrono_player_state where user_id=p_user_id;if not found or not v_state.bestiary_authority_enabled then raise exception 'Bestiário ainda não está autoritativo';end if;
  select * into v_session from public.chrono_game_sessions where id=p_session_id and user_id=p_user_id for update;if not found then raise exception 'Sessão não encontrada';end if;
  if v_session.status not in ('active','finished') then return jsonb_build_object('accepted',false,'terminal',true);end if;
  v_official_total:=greatest(coalesce(v_session.kills,0)::bigint,public.chrono_jsonb_bigint(coalesce(v_session.summary,'{}'::jsonb),array['checkpoint','kills']));
  if p_total_kills>v_official_total then raise exception 'Resumo do Bestiário maior que o checkpoint oficial';end if;
  for v_pair in select key,value from jsonb_each_text(coalesce(p_type_kills,'{}'::jsonb)) loop
    if not exists(select 1 from public.chrono_bestiary_catalog where entry_id=v_pair.key) then raise exception 'Tipo de Bestiário inválido: %',v_pair.key;end if;
    begin v_value:=v_pair.value::bigint;exception when others then raise exception 'Contagem de Bestiário inválida';end;
    if v_value<0 then raise exception 'Contagem de Bestiário inválida';end if;v_sum:=v_sum+v_value;
  end loop;
  if v_sum>greatest(0,p_total_kills) then raise exception 'Soma do Bestiário maior que o total de abates';end if;
  insert into public.chrono_bestiary_run_counters(user_id,session_id) values(p_user_id,p_session_id) on conflict(user_id,session_id) do nothing;select * into v_counter from public.chrono_bestiary_run_counters where user_id=p_user_id and session_id=p_session_id for update;
  if v_counter.finalized then return jsonb_build_object('accepted',true,'final',true,'replayed',true,'updated','{}'::jsonb);end if;
  for v_pair in select key,value from jsonb_each_text(coalesce(p_type_kills,'{}'::jsonb)) loop
    v_value:=v_pair.value::bigint;v_prev:=coalesce((v_counter.type_kills->>v_pair.key)::bigint,0);v_delta:=greatest(0,v_value-v_prev);
    if v_delta>0 then insert into public.chrono_player_bestiary(user_id,entry_id,kills) values(p_user_id,v_pair.key,v_delta) on conflict(user_id,entry_id) do update set kills=public.chrono_player_bestiary.kills+excluded.kills,updated_at=now() returning kills into v_value;v_updated:=jsonb_set(v_updated,array[v_pair.key],to_jsonb(v_value),true);end if;
    v_counter.type_kills:=jsonb_set(v_counter.type_kills,array[v_pair.key],to_jsonb(greatest(v_prev,v_pair.value::bigint)),true);
  end loop;
  update public.chrono_bestiary_run_counters set type_kills=v_counter.type_kills,finalized=finalized or p_final,updated_at=now() where user_id=p_user_id and session_id=p_session_id;
  return jsonb_build_object('accepted',true,'final',p_final,'updated',v_updated);
end;$$;

create or replace function public.chrono_bestiary_claim_server(p_user_id uuid,p_request_id uuid,p_entry_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_previous jsonb;v_state public.chrono_player_state%rowtype;v_cat public.chrono_bestiary_catalog%rowtype;v_player public.chrono_player_bestiary%rowtype;v_response jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('chrono:bestiary-claim:'||p_user_id::text||':'||p_request_id::text,0));
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;if found then return v_previous;end if;
  select * into v_state from public.chrono_player_state where user_id=p_user_id for update;if not found then raise exception 'Save online não encontrado';end if;if not v_state.bestiary_authority_enabled then raise exception 'Bestiário ainda não está autoritativo';end if;
  select * into v_cat from public.chrono_bestiary_catalog where entry_id=p_entry_id;if not found then raise exception 'Registro do Bestiário inválido';end if;
  insert into public.chrono_player_bestiary(user_id,entry_id) values(p_user_id,p_entry_id) on conflict(user_id,entry_id) do nothing;select * into v_player from public.chrono_player_bestiary where user_id=p_user_id and entry_id=p_entry_id for update;
  if v_player.claimed_at is not null then raise exception 'Recompensa do Bestiário já resgatada';end if;if v_player.kills<v_cat.required_kills then raise exception 'Registro do Bestiário ainda não concluído';end if;
  update public.chrono_player_bestiary set claimed_at=now(),updated_at=now() where user_id=p_user_id and entry_id=p_entry_id;update public.chrono_player_state set relic_shards=relic_shards+v_cat.relic_reward,revision=revision+1 where user_id=p_user_id returning * into v_state;
  v_response:=jsonb_build_object('claimed',true,'entryId',p_entry_id,'reward',v_cat.relic_reward,'payload',public.chrono_mauro_bestiary_payload_server(p_user_id));insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'bestiary_claim',v_response);return v_response;
end;$$;

-- Liquidação atômica da partida com progressão permanente e Bestiário.
-- As três etapas rodam na mesma transação PostgreSQL: se uma falhar, nenhuma
-- delas é confirmada. Isso evita uma run marcada como encerrada sem aplicar o
-- Awakening/DOOM ou os abates oficiais do Bestiário.
create or replace function public.chrono_finish_run_bundle_server(
  p_user_id uuid,
  p_request_id uuid,
  p_session_id uuid,
  p_score bigint,
  p_wave integer,
  p_kills integer,
  p_gold bigint,
  p_relic_delta integer,
  p_chrono_delta integer,
  p_boss_kills integer,
  p_elite_kills integer,
  p_skills_used integer,
  p_mission_type_kills jsonb,
  p_bestiary_type_kills jsonb,
  p_special_metrics jsonb,
  p_doom_summary jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finish jsonb;
  v_progression jsonb;
  v_bestiary jsonb;
  v_state public.chrono_player_state%rowtype;
begin
  v_finish := public.chrono_finish_run_server(
    p_user_id,
    p_request_id,
    p_session_id,
    p_score,
    p_wave,
    p_kills,
    p_gold,
    p_relic_delta,
    p_chrono_delta,
    p_boss_kills,
    p_elite_kills,
    p_skills_used,
    coalesce(p_mission_type_kills, '{}'::jsonb)
  );

  if not coalesce((v_finish ->> 'accepted')::boolean, false) then
    return v_finish;
  end if;

  v_progression := public.chrono_apply_progression_run_server(
    p_user_id,
    p_session_id,
    p_score,
    p_wave,
    p_kills,
    p_boss_kills,
    p_elite_kills,
    p_skills_used,
    coalesce(p_mission_type_kills, '{}'::jsonb),
    coalesce(p_special_metrics, '{}'::jsonb),
    coalesce(p_doom_summary, '{}'::jsonb),
    true
  );

  v_bestiary := public.chrono_apply_bestiary_run_server(
    p_user_id,
    p_session_id,
    p_kills,
    coalesce(p_bestiary_type_kills, '{}'::jsonb),
    true
  );

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id;

  return v_finish || jsonb_build_object(
    'state', to_jsonb(v_state),
    'progression', v_progression -> 'progression',
    'doomReward', coalesce((v_progression ->> 'doomReward')::integer, 0),
    'bestiary', v_bestiary,
    'bundleAtomic', true
  );
end;
$$;

create or replace function public.chrono_safe_nonnegative_bigint_server(p_value text)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare v bigint;
begin
  if p_value is null or p_value !~ '^[0-9]+$' then return 0; end if;
  begin v:=p_value::bigint; exception when others then return 0; end;
  return greatest(0,v);
end;
$$;

create or replace function public.chrono_safe_bool_server(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_value,'')) in ('true','t','1','yes','on');
$$;

-- Importação única dos sistemas locais existentes, limitada aos catálogos oficiais.
do $$
declare r public.chrono_player_state%rowtype;v_all jsonb;v_meta jsonb;v_skin jsonb;v_aug jsonb;v_power jsonb;v_claims jsonb;v_entry record;v_kills bigint;v_inv public.chrono_player_inventory%rowtype;v_legacy_reward bigint;
begin
  for r in select * from public.chrono_player_state loop
    v_legacy_reward:=0;
    v_all:=coalesce(r.save_data,'{}'::jsonb)||coalesce(r.client_save_data,'{}'::jsonb);v_meta:=coalesce(r.save_data->'chrono_v4_meta','{}'::jsonb)||coalesce(r.client_save_data->'chrono_v4_meta','{}'::jsonb);
    v_skin:=coalesce(v_all->'chrono_v4_meta_skins_clean_702','{}'::jsonb);v_aug:=coalesce(v_all->'chrono_v4_meta_chrono_augments_620','{}'::jsonb);v_power:=coalesce(v_all->'chrono_v4_meta_power_catalog_unlocks_544','{}'::jsonb);v_claims:=coalesce(v_meta->'bestiaryClaimed461','{}'::jsonb);
    insert into public.chrono_player_inventory(user_id,skins,augments,permanent_relics,catalog_powerups,selected_skins,imported_at)
    values(r.user_id,
      coalesce((select array_agg(distinct s.skin_id) from public.chrono_mauro_skin_catalog s where s.rarity<>'base' and public.chrono_safe_bool_server(v_skin->'unlocked'->>s.skin_id)),'{}'::text[]),
      coalesce((select array_agg(distinct a.augment_id) from public.chrono_mauro_augment_catalog a where public.chrono_safe_bool_server(v_aug->'unlocked'->>a.augment_id)),'{}'::text[]),
      coalesce((select array_agg(distinct c.relic_id) from public.chrono_mauro_relic_catalog c where c.relic_id=any(coalesce((select array_agg(value) from jsonb_array_elements_text(case when jsonb_typeof(v_meta->'unlockedRelics')='array' then v_meta->'unlockedRelics' else '[]'::jsonb end)),'{}'::text[]))),'{}'::text[]),
      coalesce((select array_agg(distinct p.power_id) from public.chrono_mauro_power_catalog p where public.chrono_safe_bool_server(v_power->>p.power_id)),'{}'::text[]),
      case when jsonb_typeof(v_skin->'selected')='object' then v_skin->'selected' else '{}'::jsonb end,now())
    on conflict(user_id) do update set skins=(select coalesce(array_agg(distinct x),'{}'::text[]) from unnest(public.chrono_player_inventory.skins||excluded.skins) x),augments=(select coalesce(array_agg(distinct x),'{}'::text[]) from unnest(public.chrono_player_inventory.augments||excluded.augments) x),permanent_relics=(select coalesce(array_agg(distinct x),'{}'::text[]) from unnest(public.chrono_player_inventory.permanent_relics||excluded.permanent_relics) x),catalog_powerups=(select coalesce(array_agg(distinct x),'{}'::text[]) from unnest(public.chrono_player_inventory.catalog_powerups||excluded.catalog_powerups) x),selected_skins=public.chrono_player_inventory.selected_skins||excluded.selected_skins,imported_at=coalesce(public.chrono_player_inventory.imported_at,excluded.imported_at),updated_at=now();
    for v_entry in select * from public.chrono_bestiary_catalog loop
      v_kills:=greatest(public.chrono_safe_nonnegative_bigint_server(v_meta->'bestiaryKills'->>v_entry.entry_id),public.chrono_safe_nonnegative_bigint_server(v_meta->'stats'->'typeKills'->>v_entry.entry_id));
      -- Uma marca local de resgate só é importada quando a meta também foi atingida.
      -- A recompensa é creditada uma única vez, pois o Bestiário antigo não atualizava
      -- diretamente o saldo oficial protegido no PostgreSQL.
      if public.chrono_safe_bool_server(v_claims->>v_entry.entry_id)
         and v_kills>=v_entry.required_kills
         and not exists(select 1 from public.chrono_player_bestiary p where p.user_id=r.user_id and p.entry_id=v_entry.entry_id and p.claimed_at is not null) then
        v_legacy_reward:=v_legacy_reward+v_entry.relic_reward;
      end if;
      insert into public.chrono_player_bestiary(user_id,entry_id,kills,claimed_at)
      values(r.user_id,v_entry.entry_id,greatest(0,v_kills),case when public.chrono_safe_bool_server(v_claims->>v_entry.entry_id) and v_kills>=v_entry.required_kills then now() else null end)
      on conflict(user_id,entry_id) do update set kills=greatest(public.chrono_player_bestiary.kills,excluded.kills),claimed_at=coalesce(public.chrono_player_bestiary.claimed_at,excluded.claimed_at),updated_at=now();
    end loop;
    if v_legacy_reward>0 then
      update public.chrono_player_state set relic_shards=relic_shards+v_legacy_reward,revision=revision+1 where user_id=r.user_id;
    end if;
  end loop;
end;$$;

update public.chrono_player_state set mauro_authority_enabled=true,bestiary_authority_enabled=true,collection_authority_enabled_at=coalesce(collection_authority_enabled_at,now()),revision=revision+1 where initialized=true and (not mauro_authority_enabled or not bestiary_authority_enabled);

alter table public.chrono_mauro_skin_catalog enable row level security;alter table public.chrono_mauro_augment_catalog enable row level security;alter table public.chrono_mauro_relic_catalog enable row level security;alter table public.chrono_mauro_power_catalog enable row level security;alter table public.chrono_bestiary_catalog enable row level security;alter table public.chrono_player_inventory enable row level security;alter table public.chrono_player_mauro enable row level security;alter table public.chrono_player_bestiary enable row level security;alter table public.chrono_bestiary_run_counters enable row level security;
revoke all on public.chrono_mauro_skin_catalog,public.chrono_mauro_augment_catalog,public.chrono_mauro_relic_catalog,public.chrono_mauro_power_catalog,public.chrono_bestiary_catalog,public.chrono_player_inventory,public.chrono_player_mauro,public.chrono_player_bestiary,public.chrono_bestiary_run_counters from public,anon,authenticated;
grant all on public.chrono_mauro_skin_catalog,public.chrono_mauro_augment_catalog,public.chrono_mauro_relic_catalog,public.chrono_mauro_power_catalog,public.chrono_bestiary_catalog,public.chrono_player_inventory,public.chrono_player_mauro,public.chrono_player_bestiary,public.chrono_bestiary_run_counters to service_role;
revoke all on function public.chrono_seed_mod_server(text,integer) from public,anon,authenticated;
revoke all on function public.chrono_rarity_rank_server(text) from public,anon,authenticated;
revoke all on function public.chrono_chest_roll_rarity_server(text) from public,anon,authenticated;
revoke all on function public.chrono_build_mauro_rotation_server(uuid,bigint) from public,anon,authenticated;
revoke all on function public.chrono_refresh_mauro_locked_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_mauro_bestiary_payload_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_mauro_purchase_server(uuid,uuid,text,text,integer,text) from public,anon,authenticated;
revoke all on function public.chrono_mauro_equip_skin_server(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.chrono_apply_bestiary_run_server(uuid,uuid,bigint,jsonb,boolean) from public,anon,authenticated;
revoke all on function public.chrono_bestiary_claim_server(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.chrono_finish_run_bundle_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.chrono_safe_nonnegative_bigint_server(text) from public,anon,authenticated;
revoke all on function public.chrono_safe_bool_server(text) from public,anon,authenticated;

grant execute on function public.chrono_seed_mod_server(text,integer) to service_role;
grant execute on function public.chrono_rarity_rank_server(text) to service_role;
grant execute on function public.chrono_chest_roll_rarity_server(text) to service_role;
grant execute on function public.chrono_build_mauro_rotation_server(uuid,bigint) to service_role;
grant execute on function public.chrono_refresh_mauro_locked_server(uuid) to service_role;
grant execute on function public.chrono_mauro_bestiary_payload_server(uuid) to service_role;
grant execute on function public.chrono_mauro_purchase_server(uuid,uuid,text,text,integer,text) to service_role;
grant execute on function public.chrono_mauro_equip_skin_server(uuid,uuid,text,text) to service_role;
grant execute on function public.chrono_apply_bestiary_run_server(uuid,uuid,bigint,jsonb,boolean) to service_role;
grant execute on function public.chrono_bestiary_claim_server(uuid,uuid,text) to service_role;
grant execute on function public.chrono_finish_run_bundle_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,jsonb) to service_role;
grant execute on function public.chrono_safe_nonnegative_bigint_server(text) to service_role;
grant execute on function public.chrono_safe_bool_server(text) to service_role;

comment on table public.chrono_player_inventory is 'Inventário global autoritativo: skins, Ampliações, relíquias permanentes e poderes de catálogo.';
comment on table public.chrono_player_bestiary is 'Abates e resgates oficiais dos 40 registros do Bestiário.';
comment on function public.chrono_mauro_purchase_server(uuid,uuid,text,text,integer,text) is 'Compra autoritativa da Loja do Mauro, incluindo baús com resultado determinado no servidor.';
comment on function public.chrono_finish_run_bundle_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,jsonb) is 'Liquida a run, aplica progressão e registra o Bestiário atomicamente na mesma transação.';

commit;

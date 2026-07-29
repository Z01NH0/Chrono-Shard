# Revisão técnica 8.5.14

## E-mail

A mensagem “e-mail já registrado” era ampla demais. Erros genéricos contendo termos como `duplicate` podiam ser interpretados como conflito de e-mail mesmo quando a falha real ocorria na criação do perfil, na transferência do save ou em outra tabela.

Também existia um segundo caso: uma tentativa interrompida podia criar o usuário no Supabase Auth e falhar antes da criação do perfil/save. A tentativa seguinte encontrava aquela identidade órfã e dizia que o e-mail já estava usado.

A correção agora separa:

1. formato inválido;
2. domínio inexistente ou sem registros de entrega;
3. endereço realmente vinculado a um perfil;
4. endereço realmente vinculado ao Supabase Auth;
5. identidade órfã criada pelo próprio fluxo do Chrono Shards;
6. falha interna não relacionada ao e-mail.

A limpeza automática só remove uma identidade sem perfil e sem save que esteja marcada pelos metadados do próprio Chrono Shards. Uma conta real com progresso não é apagada por essa rotina.

Um endereço como `textoaleatorio@gmail.com` possui formato e domínio válidos. Sem enviar um código/link ou usar login social, não existe forma confiável de saber se aquela caixa individual existe ou pertence ao jogador. O sistema não chama isso de e-mail confirmado.

## Transferência de conta

Foi corrigido um risco de perda de dados: se a transferência da sessão anônima terminasse, mas a abertura da nova sessão falhasse, a versão anterior poderia remover o usuário de destino e apagar o save transferido por cascata.

Agora a operação tenta reverter a transferência antes de remover a identidade incompleta. Se a reversão falhar, o destino é preservado e o servidor devolve um erro de migração pendente, evitando apagar progresso.

## Missões

A revisão encontrou estas fragilidades:

- os feitos chegavam ao servidor principalmente no fim da partida;
- patches posteriores podiam substituir os wrappers de `enemyDeath`, `useSkill`, `resetGame` ou `gameOver`;
- ao mesclar telemetrias antigas, o máximo por categoria podia ultrapassar o total de abates e rejeitar a partida inteira;
- uma falha ao criar a sessão online deixava a partida continuar sem informar claramente que ela não contaria;
- uma partida interrompida podia deixar um checkpoint sem nunca aplicá-lo às estatísticas oficiais.

Foram adicionados:

- checkpoints cumulativos aproximadamente a cada 15 segundos;
- checkpoint forçado ao ocultar a página e antes da liquidação;
- reinstalação periódica dos hooks finais;
- três tentativas para abrir a sessão da partida;
- aviso visível quando a partida não foi registrada;
- orçamento global dos tipos de inimigo no cliente, Edge Function e PostgreSQL;
- recuperação de checkpoints antigos ao abrir Missões;
- recuperação/encerramento obrigatório de runs anteriores ao iniciar uma nova;
- correção de baselines maiores que a estatística oficial.

A recuperação de checkpoint concede apenas progresso de missão. Ela não concede Relíquias, Fragmentos Chrono nem recompensas da run interrompida.

## Conferência do catálogo

O catálogo mais recente do HTML e o catálogo SQL possuem os mesmos 34 IDs, métricas e metas. A missão `Linha de Frente` exige 24 abates **com o Assault** (`classKills.assault`); abates com outro personagem não contam para esse contrato.

## Limitações honestas

- A propriedade do e-mail continua não confirmada enquanto não houver SMTP, OTP ou provedor social.
- A validação DNS confirma o domínio, não a caixa postal individual.
- A Edge Function e a migration foram validadas estaticamente, mas o teste definitivo depende de executá-las no projeto Supabase real.

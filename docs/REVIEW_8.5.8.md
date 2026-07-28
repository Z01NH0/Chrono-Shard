# Revisão técnica — Chrono Shards 8.5.8

## Fluxos revisados

- Primeira abertura sem sessão.
- Continuação como convidado.
- Registro sobre uma sessão anônima existente.
- Login em conta existente.
- Troca de conta sem mistura de `localStorage`.
- Logout e criação de nova sessão convidada.
- Recuperação e alteração de senha.
- Rotação da chave de recuperação.
- Inicialização e sincronização automática do save.
- Compras, recompensas de partida, missões e códigos já integrados.

## Problemas encontrados e corrigidos

1. O save ainda dependia de cache local para sistemas não migrados. Foi criado `client_save_data` no Supabase.
2. Uma sincronização genérica poderia sobrescrever dados autoritativos. O snapshot agora fica em coluna separada e o cliente sempre sobrepõe saldos/desbloqueios com os valores oficiais.
3. Contas novas poderiam abusar da migração inicial para importar recursos falsos. A inicialização nova agora zera recursos e remove desbloqueios protegidos.
4. A troca de senha enviava um campo não suportado ao cliente Auth. O fluxo foi corrigido.
5. A recuperação bloqueava globalmente a conta-alvo, permitindo negação de serviço. O limite agora é aplicado ao solicitante e ao usuário-alvo daquela tentativa.
6. O módulo de tutorial tinha uma chave de progresso fora do snapshot. Ela foi incluída.
7. O painel técnico oculto de economia ainda executava observadores. Ele foi desativado.

## Limites conhecidos

- O e-mail de contato não é verificado sem SMTP.
- A chave de recuperação é a única recuperação independente do dispositivo; perdê-la significa depender de suporte manual.
- Sistemas ainda não autoritativos podem ser adulterados localmente até sua migração específica. Eles são sincronizados para conveniência, não tratados como prova confiável.
- A validação foi estática e de consistência. O teste final precisa ser realizado no projeto Supabase real após aplicar SQL e Edge Function.

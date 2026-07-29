# Changelog 8.5.16

- Corrigido progresso de missões sendo sobrescrito como `0/1`.
- RPC de missões passa a devolver progresso autoritativo completo.
- Missões são hidratadas automaticamente no boot da conta.
- Troca entre Geral e Awakening mantém o mesmo estado oficial.
- Cliente deixa de sortear missões quando o servidor já é a autoridade.
- Cooldown vencido solicita nova missão ao servidor.
- Adicionada compatibilidade com RPC antiga para evitar regressão durante atualização.
- Recuperação de checkpoint abandonado aumentada para 180 segundos.
- Adicionado diagnóstico SQL específico para rotação, baseline e progresso.

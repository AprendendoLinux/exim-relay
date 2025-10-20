# Exim-Relay: Um Relay SMTP Simples com Docker e Exim4

## Descrição - Meu pau na sua mão

Este repositório fornece uma configuração Docker para um relay SMTP usando o Exim4, um servidor de e-mail leve e flexível. O objetivo é criar um contêiner que atue como um relay para enviar e-mails através de um servidor SMTP externo (como o Gmail ou outro provedor), com suporte a decodificação de assuntos (subjects) codificados nos logs para facilitar a depuração. Isso é útil para ambientes de desenvolvimento, testes ou aplicações que precisam enviar e-mails sem configurar um servidor SMTP completo.

Principais recursos:
- Relay SMTP usando Exim4 configurado como "smarthost".
- Suporte a autenticação SMTP para o servidor externo.
- Decodificação automática de assuntos MIME e octais nos logs (via script Python).
- Configuração flexível via variáveis de ambiente.
- Logs decodificados salvos em `/var/log/exim4/mail.log`.
- Suporte a restrição de redes de origem para relay (via `dc_relay_nets`).
- Suporte a envio direto (sem relay externo) ou relay autenticado.
- Assinatura DKIM com geração automática de chaves para domínios permitidos (opcional para envio direto).
- Restrição de domínios remetentes permitidos (opcional para envio direto).
- Configuração de protocolo de rede (IPv4 ou all, opcional para envio direto).

Este projeto é ideal para aprender sobre configuração de e-mail no Linux, Docker e Exim4.

## Pré-requisitos

- Docker instalado (versão 20+ recomendada).
- Docker Compose instalado (versão 2+ recomendada).
- Acesso a um servidor SMTP externo (ex.: Gmail SMTP relay) com credenciais de autenticação (opcional para envio direto).
- Conhecimento básico de Docker e variáveis de ambiente.

## Instalação

1. Clone o repositório:
   ```bash
   git clone https://github.com/AprendendoLinux/exim-relay.git
   cd exim-relay
   ```

2. Crie um diretório para logs (opcional, mas recomendado para persistência):
   ```bash
   mkdir logs
   ```

3. Configure as variáveis de ambiente no `docker-compose.yml` (veja a seção de Configuração abaixo).

4. Inicie o contêiner:
   ```bash
   docker-compose up -d
   ```

   **Nota**: A imagem `aprendendolinux/exim-relay:latest` será baixada automaticamente do Docker Hub. Não é necessário compilar localmente.

5. Verifique se o contêiner está rodando:
   ```bash
   docker ps
   docker logs exim-relay
   ```

## Configuração

A configuração principal é feita via variáveis de ambiente no arquivo `docker-compose.yml`. Abaixo está uma versão comentada do arquivo, com explicações para cada variável. Substitua os placeholders `[your-username]`, `[your-password]` e `[your-hostname]` por valores válidos, garantindo que as credenciais sejam compatíveis com o servidor SMTP externo. **Nunca commite informações sensíveis no GitHub.**

```yaml
services:
  mail-relay:
    image: aprendendolinux/exim-relay:latest  # Imagem pré-construída no Docker Hub
    container_name: exim-relay  # Nome do contêiner para fácil identificação
    environment:
      - SMTP_SERVER=  # Deixe vazio para envio direto ou especifique relay (ex.: smtp-relay.gmail.com)
      - SMTP_PORT=25  # Porta do servidor SMTP (25 para envio direto, 587 para TLS/STARTTLS, 465 para SSL)
      - SMTP_USERNAME=  # Usuário para autenticação SMTP (opcional para envio direto, ex.: seu email)
      - SMTP_PASSWORD=  # Senha para autenticação SMTP (opcional para envio direto, use app password para Gmail com 2FA)
      - SERVER_HOSTNAME=[your-hostname]  # Nome do host do servidor (FQDN usado para qualificação de domínio no Exim)
      - TZ=America/Sao_Paulo  # Fuso horário do contêiner (ex.: America/Sao_Paulo para horário de Brasília)
      - DECODE_SUBJECT=yes  # Ativa decodificação de assuntos nos logs (yes/no)
      - DECODE_DEBUG=yes  # Ativa modo debug no decode_log.py (yes/no, exibe detalhes de decodificação)
      - RELAY_NETS=0.0.0.0/0  # Redes permitidas para relay (ex.: 172.16.0.0/12;192.168.0.0/16 para redes específicas; 0.0.0.0/0 para qualquer origem)
      - ALLOWED_SENDER_DOMAINS=  # Domínios de remetentes permitidos (opcional para relay autenticado, espaço-separados)
      - DKIM_SELECTOR=mail  # Selector DKIM (opcional para relay autenticado, padrão: mail)
      - DKIM_AUTOGENERATE=no  # Gera chaves DKIM automáticas se não existirem (opcional para relay autenticado, yes/no)
      - EXIM_INET_PROTOCOLS=all  # Protocolo de rede: ipv4 ou all (opcional para relay autenticado)
    volumes:
      - /srv/exim/logs:/var/log/exim4  # Monta diretório local para persistir logs (ex.: ./logs:/var/log/exim4)
      - /srv/exim/dkim:/etc/opendkim/keys  # Monta diretório para chaves DKIM (similar ao postfix)
    restart: unless-stopped  # Política de restart (reinicia automaticamente, exceto se parado manualmente)
    ports:
      - 25:25  # Expõe a porta 25 do contêiner para conexões SMTP externas
```

### Variáveis explicadas
- `SMTP_SERVER`: Endereço do servidor SMTP externo para relay (ex.: `smtp-relay.gmail.com`). Deixe vazio para envio direto.
- `SMTP_PORT`: Porta para conexão SMTP. Use `587` para STARTTLS (recomendado) ou `465` para SSL. Para envio direto, use `25`.
- `SMTP_USERNAME`: Usuário para autenticação SMTP. Para Gmail, use o e-mail ou um app-specific username (opcional para envio direto).
- `SMTP_PASSWORD`: Senha ou app password (necessário para contas com autenticação de dois fatores; opcional para envio direto).
- `SERVER_HOSTNAME`: Nome do host (FQDN) usado pelo Exim para qualificar domínios. Exemplo: `mail.suaempresa.com`.
- `TZ`: Fuso horário do contêiner, para timestamps corretos nos logs (ex.: `America/Sao_Paulo`).
- `DECODE_SUBJECT`: Ativa o script `decode_log.py` para decodificar assuntos MIME/octais nos logs (`yes` para ativar, `no` para desativar).
- `DECODE_DEBUG`: Ativa logs detalhados no `decode_log.py` (`yes` para exibir detalhes no `/var/log/exim4/decode_errors.log`).
- `RELAY_NETS`: Redes ou IPs permitidos para relay, no formato Exim (ex.: `172.16.0.0/12;192.168.0.0/16` para múltiplas redes; `0.0.0.0/0` para qualquer origem). Separe múltiplas redes com `;` (sem espaços).
- `ALLOWED_SENDER_DOMAINS`: Domínios permitidos para remetentes (espaço-separados; opcional para relay autenticado). Se definido, o Exim rejeita envios de domínios não listados.
- `DKIM_SELECTOR`: Seletor DKIM para chaves geradas (padrão: `mail`; opcional para relay autenticado).
- `DKIM_AUTOGENERATE`: Ativa a geração automática de chaves DKIM para domínios permitidos (`yes` para ativar, `no` para desativar; opcional para relay autenticado).
- `EXIM_INET_PROTOCOLS`: Protocolo de rede para envio direto (`ipv4` para apenas IPv4, `all` para IPv4 e IPv6; opcional para relay autenticado).

Após alterar o `docker-compose.yml`, reinicie o contêiner:
```bash
docker-compose up -d
```

## Uso

1. **Enviar e-mails**:
   - Use um cliente SMTP (como `swaks`, `telnet`, ou sua aplicação) para enviar e-mails através do contêiner na porta 25.
   - Exemplo com `swaks` (instale via `sudo apt install swaks`):
     ```bash
     swaks --to destinatario@example.com --from remetente@example.com --server localhost:25 --auth LOGIN --auth-user [your-username] --auth-password [your-password]
     ```
   - O Exim relaya o e-mail para o servidor externo configurado.

2. **Monitorar logs**:
   - **Logs brutos**: `/var/log/exim4/mainlog` contém os logs originais do Exim, com assuntos não decodificados (ex.: `T="Ol\303\241, tudo bem?? =,?"`).
     ```bash
     docker exec exim-relay cat /var/log/exim4/mainlog
     ```
   - **Logs decodificados**: `/var/log/exim4/mail.log` contém logs com assuntos decodificados (ex.: `T="Olá, tudo bem??"`).
     ```bash
     docker exec exim-relay cat /var/log/exim4/mail.log
     ```
   - **Erros de decodificação**: `/var/log/exim4/decode_errors.log` contém logs de depuração do `decode_log.py` (útil com `DECODE_DEBUG=yes`).
     ```bash
     docker exec exim-relay cat /var/log/exim4/decode_errors.log
     ```
   - **Rejeições**: `/var/log/exim4/rejectlog` registra tentativas de conexão rejeitadas (ex.: falta de autenticação ou domínios não permitidos).
     ```bash
     docker exec exim-relay cat /var/log/exim4/rejectlog
     ```

3. **Depuração**:
   - Ative `DECODE_DEBUG=yes` para ver detalhes de decodificação no `decode_errors.log`.
   - Verifique `/var/log/exim4/rejectlog` para conexões rejeitadas devido a redes não permitidas ou falta de autenticação.
   - Use `docker logs exim-relay` para ver a saída do pipeline (logs decodificados e mensagens de inicialização).

## Segurança

- **Restrição de redes**:
  - A variável `RELAY_NETS` controla quais redes podem usar o relay. Evite `0.0.0.0/0` em ambientes públicos, pois isso permite conexões de qualquer origem, aumentando o risco de spam ou abuso.
  - Use redes específicas (ex.: `172.16.0.0/12;192.168.0.0/16`) para limitar o acesso a hosts confiáveis.
- **Autenticação**:
  - O Exim está configurado com uma ACL (`acl_check_mail`) que exige autenticação SMTP, rejeitando conexões não autenticadas.
- **Firewall**:
  - Restrinja a porta 25 no host Docker a IPs confiáveis usando um firewall (ex.: `iptables` ou regras do provedor de nuvem).
- **Credenciais**:
  - Nunca inclua `SMTP_USERNAME` ou `SMTP_PASSWORD` diretamente no `docker-compose.yml` em repositórios públicos. Use arquivos `.env` ou segredos do Docker.
  - Exemplo de `.env`:
    ```bash
    SMTP_USERNAME=seu-email@example.com
    SMTP_PASSWORD=sua-senha
    ```
    Atualize o `docker-compose.yml` para usar o `.env`:
    ```yaml
    environment:
      - SMTP_USERNAME=${SMTP_USERNAME}
      - SMTP_PASSWORD=${SMTP_PASSWORD}
    ```
- **TLS**:
  - O contêiner usa um certificado autoassinado por padrão, gerando um aviso nos logs. Para produção, configure um certificado TLS válido (ex.: Let's Encrypt).
- **Atualizações**:
  - Mantenha a imagem `aprendendolinux/exim-relay:latest` atualizada com `docker pull aprendendolinux/exim-relay:latest`.

## Estrutura do Projeto

- `docker-compose.yml`: Define o serviço Docker, incluindo variáveis de ambiente e configurações de volume/portas.
- `run.sh`: Script interno que configura o Exim4, autenticação, logs e inicia o pipeline de decodificação (se `DECODE_SUBJECT=yes`).
- `decode_log.py`: Script Python que decodifica assuntos MIME e octais nos logs, salvando em `/var/log/exim4/mail.log`.

**Nota**: Os arquivos `run.sh` e `decode_log.py` estão incluídos na imagem `aprendendolinux/exim-relay:latest` e não precisam ser fornecidos localmente, a menos que você queira personalizar a imagem.

## Personalização (Opcional)

Se você precisar personalizar a configuração:
1. Baixe a imagem e extraia os arquivos internos:
   ```bash
   docker create --name temp-exim aprendendolinux/exim-relay:latest
   docker cp temp-exim:/run.sh .
   docker cp temp-exim:/decode_log.py .
   docker rm temp-exim
   ```
2. Crie um `Dockerfile` local para modificações:
   ```dockerfile
   FROM aprendendolinux/exim-relay:latest
   COPY run.sh /run.sh
   COPY decode_log.py /decode_log.py
   RUN chmod +x /run.sh /decode_log.py
   ```
3. Atualize o `docker-compose.yml` para usar build local:
   ```yaml
   services:
     mail-relay:
       build:
         context: .
         dockerfile: Dockerfile
       # ... resto do arquivo ...
   ```
4. Construa e inicie:
   ```bash
   docker-compose build
   docker-compose up -d
   ```

## Resolução de Problemas

- **Assunto não decodificado em `/var/log/exim4/mail.log`**:
  - Verifique se `DECODE_SUBJECT=yes` está no `docker-compose.yml`.
  - Consulte `/var/log/exim4/decode_errors.log` para erros do `decode_log.py`.
  - Confirme que `/var/log/exim4/mail.log` está sendo escrito:
    ```bash
    docker exec exim-relay cat /var/log/exim4/mail.log
    ```
- **Erro "Network is unreachable"**:
  - Ocorre devido a tentativas de conexão IPv6. A configuração `EXIM_INET_PROTOCOLS=ipv4` já mitiga isso. Confirme no `docker-compose.yml`.
- **Erro "TLS error on connection"**:
  - Pode ocorrer em conexões instáveis com o servidor SMTP externo. Verifique a conectividade de rede e as credenciais.
- **Conexões rejeitadas**:
  - Consulte `/var/log/exim4/rejectlog` para detalhes.
  - Certifique-se de que o IP remetente está em `RELAY_NETS` e que a autenticação está correta.
- **Logs do contêiner**:
  - Use `docker logs exim-relay` para mensagens de inicialização e logs decodificados.
- **Imagem desatualizada**:
  - Atualize com:
    ```bash
    docker pull aprendendolinux/exim-relay:latest
    docker-compose up -d
    ```

## Contribuição

Contribuições são bem-vindas! Para contribuir:
1. Fork o repositório.
2. Crie uma branch (`git checkout -b feature/nova-feature`).
3. Commit suas alterações (`git commit -m "Adiciona nova feature"`).
4. Push para a branch (`git push origin feature/nova-feature`).
5. Abra um Pull Request.

## Suporte

Se tiver dúvidas ou problemas, abra uma issue no GitHub: [https://github.com/AprendendoLinux/exim-relay/issues](https://github.com/AprendendoLinux/exim-relay/issues).

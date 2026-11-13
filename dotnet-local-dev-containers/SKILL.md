---
name: dotnet-local-dev-containers
description: Ambiente local e testes de integração com containers para projetos .NET - Docker Compose para desenvolvimento (compose.yaml, healthcheck + depends_on condition, volumes, profiles, secrets, arquivos de override, versões fixas) e Testcontainers for .NET para testes automatizados (módulos PostgreSql/MsSql/Redis/RabbitMq/MongoDb, xUnit ContainerTest/ContainerFixture, wait strategies, Ryuk, reuso, portas/nomes aleatórios, CI, WebApplicationFactory). Use quando o usuário pedir subir banco/Redis/RabbitMQ/Seq local, criar docker-compose de dev, ou testes de integração contra infraestrutura real. Based on official docs - Docker Compose (docs.docker.com) e Testcontainers for .NET (dotnet.testcontainers.org) - fontes externas à Microsoft.
---

# Containers para desenvolvimento e testes (.NET)

**Proveniência:** **[DOCKER]** documentação oficial do **Docker Compose**; **[TC]** documentação oficial do **Testcontainers for .NET** (série **4.x**; a estável atual no NuGet é a 4.16); ambas são **externas à Microsoft**. **[RMQ]** documentação do RabbitMQ. Comandos/flags não lidos estão marcados. **CONVENÇÃO** = escolha minha.
**Quando usar o quê:** **Docker Compose** = ambiente de **desenvolvimento** que o dev sobe e mantém (app + banco/Redis/RabbitMQ/Seq); **Testcontainers** = infraestrutura **descartável criada pelo próprio teste** (isolada, reproduzível, limpa ao final). Alternativa de orquestração em dev: .NET Aspire (não coberto).
Ligações: `dotnet-integration-testing`, `efcore-testing`, `dotnet-test-automation`, `dotnet-xunit`, `dotnet-rabbitmq`, `dotnet-redis`, `dotnet-serilog`, `dotnet-ci-cd`, `dotnet-project-standards`, `aspnet-configuration-options`.

## Docker Compose para desenvolvimento [DOCKER]
- **Arquivo:** `compose.yaml` (**preferido**) ou `compose.yml` na pasta de trabalho (`docker-compose.yml/yaml` são aceitos por compatibilidade). O elemento **`version:` é obsoleto** (só informativo; gera aviso) — omita. Nome do projeto Compose pode ser definido para rodar o mesmo arquivo duas vezes sem conflito.
- **Ordem de inicialização:** o Compose cria serviços em **ordem de dependência** (`depends_on`, `links`, `volumes_from`, `network_mode: service:`) e remove na ordem inversa, mas **"não espera o container ficar pronto, só estar em execução"**. Para esperar prontidão use **`depends_on` com `condition`**: `service_started`, **`service_healthy`** (exige um `healthcheck` na dependência) ou **`service_completed_successfully`** (ex.: container de migração que roda e termina). `restart: true` reinicia o dependente quando a dependência é reiniciada por operação do Compose.
- **Healthcheck:** `test`, `interval`, `timeout`, `retries`, `start_period`. Exemplo oficial (Postgres): `test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]` (note o `$$` para escapar). RabbitMQ: a doc do broker indica `rabbitmq-diagnostics -q ping` (e `check_running`) como verificação [RMQ]. Redis: `redis-cli ping` (comando `PING`; **não lido** nesta pesquisa). Para os demais serviços, consulte a doc da imagem.
- **Segredos:** variáveis de ambiente ficam visíveis a todos os processos e **podem ir parar em logs de erro**; **secrets** montam o valor como arquivo em **`/run/secrets/<nome>`** (definidos no elemento `secrets` de topo e referenciados por serviço; **só containers Linux**). Em dev local, credenciais descartáveis em `.env`/`environment` são aceitáveis (**CONVENÇÃO**), **nunca** segredos reais/de produção (`dotnet-security-review`).
- **Profiles** (`profiles: [nome]`): serviços opcionais (ex.: Seq, pgAdmin) só sobem com `--profile nome`.
- **Produção/outros ambientes:** a doc sugere um arquivo adicional (ex.: `compose.production.yaml`) só com as diferenças — remover bind mounts de código, mudar portas, variáveis, **`restart`**, serviços extras. Aqui o foco é **dev**; deploy real: `aspnet-hosting-deployment`.
- **Volumes nomeados** para persistir dados entre `down`/`up` (CONVENÇÃO: quem quer estado limpo remove o volume ao derrubar).
- **Exemplo (esqueleto; fixe as versões das imagens — não use `latest`):**
```yaml
services:
  db:
    image: postgres:<versão>
    environment: { POSTGRES_USER: app, POSTGRES_PASSWORD: dev-only, POSTGRES_DB: app }
    ports: ["5432:5432"]
    volumes: [dbdata:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      retries: 5
      start_period: 30s
      timeout: 10s
  rabbitmq:
    image: rabbitmq:<versão>-management
    ports: ["5672:5672", "15672:15672"]
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      retries: 5
  redis:
    image: redis:<versão>
    ports: ["6379:6379"]
  api:                       # opcional: rodar o app também no Compose
    build: .
    depends_on:
      db: { condition: service_healthy, restart: true }
      rabbitmq: { condition: service_healthy }
      redis: { condition: service_started }
    environment:
      ConnectionStrings__Default: "Host=db;Database=app;Username=app;Password=dev-only"
volumes: { dbdata: {} }
```
- **Conectar o app:** de **dentro** da rede do Compose use o **nome do serviço** como host; **do host** (app rodando na IDE) use `localhost` + porta publicada. Passe a configuração por variáveis (`ConnectionStrings__Default`, `Serilog__...`) ou **user-secrets** (`aspnet-configuration-options`). O `guest` do RabbitMQ **só conecta de localhost** [RMQ] — em dev com container crie usuário próprio. Dev ≠ produção (sem TLS/ACL de produção): não copie para o ambiente real.
- **Comandos básicos:** `docker compose up -d`, `docker compose logs -f <serviço>`, `docker compose down`. *(Flags como `--wait` e `down -v` (remover volumes) não foram lidas nesta pesquisa — confirme com `docker compose up --help` / `docker compose down --help`.)*

## Testcontainers for .NET para testes [TC]
- **Pacotes:** `Testcontainers` (core) + **módulos** prontos (`Testcontainers.PostgreSql`, `.MsSql`, `.Redis`, `.RabbitMq`, `.MongoDb`, `.Elasticsearch`, `.ServiceBus`, `.Azurite`...). Integração com xUnit: **`Testcontainers.XunitV3`** (xUnit v3) ou **`Testcontainers.Xunit`** (v2).
- **Uso básico (série 4.x — a imagem vai no construtor do builder):**
```csharp
var postgres = new PostgreSqlBuilder("postgres:15.1").Build();   // fixe a versão da imagem
await postgres.StartAsync();
var connectionString = postgres.GetConnectionString();
```
- **xUnit — contexto isolado × compartilhado:** herde **`ContainerTest<TBuilder, TContainer>`** para **um container novo por teste** (isolamento total, bom para operações destrutivas; sobrescreva `Configure(builder)` e **fixe a imagem**) ou **`ContainerFixture<TBuilder, TContainer>`** para **compartilhar** um container entre os testes da classe (ou do assembly, com xUnit v3/extensão) quando criar é caro. Alternativa: `IAsyncLifetime` (`InitializeAsync` inicia, `DisposeAsync` descarta). O fixture usa `IMessageSink` (não `ITestOutputHelper`) para repassar logs.
- **Boas práticas oficiais (8):** (1) **sem nomes estáticos** para containers/redes/volumes (Docker gera nomes aleatórios); (2) **sem porta fixa** — `WithPortBinding(porta, true)` e leia `GetMappedPublicPort(porta)`; (3) **não use `localhost`/`127.0.0.1`** — use `container.Hostname`; (4) entre containers use **network aliases** e a porta interna; (5) evite montar paths do host — use `WithResourceMapping` para copiar arquivos; (6) para propriedades não expostas use `WithCreateParameterModifier`; (7) **não desabilite o Resource Reaper**; (8) **fixe a versão da imagem** (`WithImage("alpine:3.20.0")`), nunca `latest`.
- **Wait strategies:** por padrão o Testcontainers espera só o container **estar rodando** — para a maioria das imagens **não basta**. Encadeie: `Wait.ForUnixContainer().UntilInternalTcpPortIsAvailable(80)`, `.UntilHttpRequestIsSucceeded(r => r.ForPath("/"))`, `.UntilMessageIsLogged("Server started", o => o.WithTimeout(...))`, `.UntilFileExists(...)`, ou implemente a sua. **`WaitStrategyMode.OneShot`** para containers que terminam normalmente (migração). **Padrões globais:** tentativas **infinitas**, intervalo **1 s**, timeout **1 h** (ajustáveis por propriedades/variáveis `TESTCONTAINERS_WAIT_STRATEGY_*`) — defina **timeouts razoáveis** para o teste não pendurar o CI. Cancelar a subida: `CancellationToken`. Módulos já trazem a estratégia correta.
- **Resource Reaper (Ryuk):** remove os recursos Docker ao fim dos testes (passando ou falhando); **não desabilite** — só em ambientes com limpeza própria (ex.: nós de CI efêmeros); só containers Linux; por padrão roda **privilegiado** (`ryuk.container.privileged = true`) e a imagem é fixada por digest (copie para registry privado com preservação do manifest list se necessário). Bitbucket Pipelines **não suporta** Ryuk.
- **Reuso (`WithReuse(true)`):** **experimental**; mantém o container entre execuções (acelera o loop de dev) mas **desabilita o Reaper** (nada é limpo) e o hash do builder **pode colidir** — use `WithLabel("reuse-id", ...)`. **CONVENÇÃO:** só no desenvolvimento local, nunca no CI.
- **Configuração do runtime Docker:** `~/.testcontainers.properties` ou variáveis (`DOCKER_HOST`, `DOCKER_CONTEXT`, `TESTCONTAINERS_HOST_OVERRIDE`, `TESTCONTAINERS_RYUK_DISABLED`, ...); suporta Docker remoto.
- **ASP.NET Core:** com `WebApplicationFactory<Program>` injete a connection string **antes** de criar o TestServer — `builder.UseSetting("ConnectionStrings:RedisCache", container.GetConnectionString())` (container já iniciado) ou uma `IConfigurationSource` própria que inicia a dependência. Ver `dotnet-integration-testing`.
- **Banco real nos testes:** aplique as **migrations** no container antes do teste e isole dados por teste/classe (`efcore-testing`: a doc de EF recomenda testar contra o banco real do provider; InMemory não substitui). **CONVENÇÃO:** um container compartilhado por classe/assembly + limpeza de dados entre testes costuma equilibrar custo e isolamento.
- **CI [TC]:** só exige **Docker** (local ou remoto). **GitHub-hosted runners e agentes Microsoft-hosted já têm Docker**; agentes **Windows usam o engine Windows e não rodam imagens Linux**; GitLab: Docker-in-Docker (`services: [docker:dind]` + `DOCKER_HOST: tcp://docker:2375`). Veja `dotnet-ci-cd`.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Imagens com `latest`/sem versão fixa no Compose ou nos testes | Média |
| 2 | `depends_on` sem `condition: service_healthy` e sem healthcheck (app sobe antes do banco/broker) | Média |
| 3 | Credenciais reais/de produção em `compose.yaml`, `.env` versionado ou testes | Alta |
| 4 | Testes com porta/nome fixos, `localhost` fixo em vez de `Hostname`/porta mapeada (colisão em paralelo/CI) | Média |
| 5 | Ryuk desabilitado fora de CI efêmero; `WithReuse` no CI | Média |
| 6 | Wait strategy padrão ("só running") em imagem que precisa de prontidão; sem timeout (pendura o pipeline) | Média |
| 7 | Um container por teste quando um fixture compartilhado bastaria (suíte lenta) — ou estado compartilhado sem limpeza (testes flaky) | Média |
| 8 | Testes de integração com EF usando InMemory em vez do banco real em container | Média |
| 9 | Compose de dev copiado para produção (sem TLS/ACL/volumes/restart adequados) | Alta |
| 10 | Volumes de dados sem decisão (estado antigo causando falha) ou `down -v` acidental em dado importante | Baixa |
| 11 | Pipeline sem Docker disponível (agente Windows com imagens Linux; DinD sem `DOCKER_HOST`) | Média |

## Fontes
**[DOCKER]** Compose — ordem de inicialização (`depends_on`/healthcheck): https://docs.docker.com/compose/how-tos/startup-order/ · Segredos: https://docs.docker.com/compose/how-tos/use-secrets/ · Profiles: https://docs.docker.com/compose/how-tos/profiles/ · Produção: https://docs.docker.com/compose/how-tos/production/ · Referência de `services`: https://docs.docker.com/reference/compose-file/services/ · Versão/nome: https://docs.docker.com/reference/compose-file/version-and-name/
**[TC]** Testcontainers for .NET — início: https://dotnet.testcontainers.org/ · Boas práticas: https://dotnet.testcontainers.org/api/best_practices/ · Wait strategies: https://dotnet.testcontainers.org/api/wait_strategies/ · Resource Reaper: https://dotnet.testcontainers.org/api/resource_reaper/ · Reuso: https://dotnet.testcontainers.org/api/resource_reuse/ · xUnit: https://dotnet.testcontainers.org/test_frameworks/xunit_net/ · Módulos: https://dotnet.testcontainers.org/modules/ · ASP.NET Core: https://dotnet.testcontainers.org/examples/aspnet/ · CI: https://dotnet.testcontainers.org/cicd/ · Configuração: https://dotnet.testcontainers.org/custom_configuration/
**[RMQ]** Monitoramento/health checks: https://www.rabbitmq.com/docs/monitoring

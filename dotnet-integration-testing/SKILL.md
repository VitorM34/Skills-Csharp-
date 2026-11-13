---
name: dotnet-integration-testing
description: Escrever e revisar testes de integração de APIs ASP.NET Core - WebApplicationFactory, TestServer, HttpClient em memória, IClassFixture, substituir serviços e banco (ConfigureTestServices), mock de autenticação, configuração e ambiente de teste, Microsoft.AspNetCore.Mvc.Testing, isolamento de dados. Use quando o usuário pedir teste de integração, testar endpoints de ponta a ponta ou verificar se os testes de integração estão corretos. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Testes de integração no ASP.NET Core — escrever e revisar

Só afirmar o que a doc oficial diz (fontes no fim). Estratégia geral: `dotnet-test-automation`. Banco de dados: `efcore-testing`. Unitários: `dotnet-unit-testing`.

## O que são (doc)
Verificam que componentes funcionam juntos **incluindo a infraestrutura** (banco, sistema de arquivos, rede, pipeline de request/response). Diferem dos unitários: usam **componentes reais de produção**, exigem mais código e dados, são mais lentos. Por isso:
- limite-os aos cenários de infraestrutura mais importantes; **se der para testar com unitário, use unitário**;
- **não teste todas as permutações** de dados/arquivos; um conjunto focado de leitura/escrita/atualização/exclusão basta, e a lógica do método vai em unitário (com fakes, mais rápido);
- **projetos separados** de unitários e integração.
O projeto testado é o **SUT** (System Under Test). Para SPAs, a doc recomenda **Playwright for .NET** (automatiza navegador).

## Pré-requisitos do projeto de teste
- Referenciar `Microsoft.AspNetCore.Mvc.Testing`.
- `<Project Sdk="Microsoft.NET.Sdk.Web">` no projeto de teste.
- Framework de teste (ex.: `xunit`, `xunit.runner.visualstudio`) e, com `xunit.runner.visualstudio` ≥ 2.4.2, `Microsoft.NET.Test.Sdk`.
- O pacote copia o `.deps` do SUT para o `bin` do teste, define o **content root** como a raiz do SUT e fornece `WebApplicationFactory<TEntryPoint>`.
- `TEntryPoint` é a classe de entrada do SUT, normalmente `Program`. (A página lida não detalha como tornar `Program` acessível ao projeto de teste quando é top-level; confirme na doc/ao compilar antes de afirmar a técnica.)
- Sem ambiente definido, o SUT roda como `Development`. Para definir o ambiente, faça na factory customizada.

## Fluxo de um teste (doc)
1. Host do SUT configurado → 2. cliente do test server criado → 3. **Arrange**: prepara a requisição → 4. **Act**: cliente envia e recebe resposta → 5. **Assert**: valida resposta real × esperada.

## Teste básico
```csharp
public class BasicTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;
    public BasicTests(WebApplicationFactory<Program> factory) => _factory = factory;

    [Theory]
    [InlineData("/")]
    public async Task Get_EndpointsReturnSuccess(string url)
    {
        var client = _factory.CreateClient();          // segue redirects e trata cookies por padrão
        var response = await client.GetAsync(url);
        response.EnsureSuccessStatusCode();            // 200-299
    }
}
```
- `IClassFixture` compartilha a factory entre os testes da classe; `TestServer` e `HttpClient` são descartados quando o xUnit descarta a factory (MSTest: `ClassCleanup`; NUnit: `TearDown`). Objetos que você criar e exigirem descarte, descarte você no fixture.
- Nomeie por classe testada: Razor Pages → `IndexPageTests`; MVC/controllers → `HomeControllerTests`.

## Customizar a factory
```csharp
public class CustomWebApplicationFactory<TProgram> : WebApplicationFactory<TProgram> where TProgram : class
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // remover o descritor do DbContext registrado no Program.cs e adicionar outro para o teste
        });
        builder.UseEnvironment("Development");   // exemplo de ambiente
    }
}
```
- O callback de serviços do teste roda **depois** do `Program.cs` do SUT: para trocar o banco, **remova o descritor do contexto registrado** e registre o de teste.
- Para trocar o **banco**, a doc de EF Core **desencoraja** o provider InMemory como substituto (ver `efcore-testing`). O sample da doc de integração usa InMemory por simplicidade; **prefira o banco real do seu provedor**.
- **Configuração:** `builder.ConfigureAppConfiguration(c => c.AddInMemoryCollection(...))` (preservada, mas só disponível depois do `Build`) ou `ConfigureHostConfiguration` via `CreateHost` (disponível antes do entry point; **passe `args` ao `WebApplication.CreateBuilder`**, senão não surte efeito).
- **Por teste:** `_factory.WithWebHostBuilder(b => ...)` cria nova factory customizada (ex.: re-seed do banco, trocar serviço).
- **Opções do cliente:** `WebApplicationFactoryClientOptions` em `CreateClient(options)`; `AllowAutoRedirect = false` permite assertar o **redirect** (status e header `Location`) em vez do destino final; `BaseAddress = new Uri("https://localhost")` evita avisos de redirecionamento HTTPS.

## Substituir serviços (mocks)
`builder.ConfigureTestServices(services => services.AddScoped<IQuoteService, TestQuoteService>())` dentro de `WithWebHostBuilder`: restringe o override ao teste. Boa prática: dependências externas (APIs de terceiros, e-mail) trocadas por fakes; o que é da sua infraestrutura (banco) fica real.

## Autenticação
Mock de `AuthenticationHandler<AuthenticationSchemeOptions>` que retorna `AuthenticateResult.Success(...)`, registrado em `ConfigureTestServices` com `AddAuthentication("TestScheme")...`. O **esquema deve casar** com o que o app espera, senão a autenticação não funciona. Teste também o caso **não autenticado** (redirect/401) com `AllowAutoRedirect = false`.

## Outros detalhes da doc
- Cookies não essenciais não persistem entre requisições com política GDPR ligada: marque como essenciais nos testes.
- Antiforgery em Razor Pages/MVC: a doc usa AngleSharp para parsear HTML, ou *Application Parts* para pegar tokens por JSON.
- Content root inferido via `WebApplicationFactoryContentRootAttribute` ou procurando o `.sln`.
- Shadow copying (xUnit) pode atrapalhar testes que carregam arquivos relativos a `Assembly.Location`: `xunit.runner.json` com `{"shadowCopy": false}`.
- Testes que alteram dados e compartilham banco podem interferir: re-seed por teste ou isolamento (ver `efcore-testing`).


## Testar middleware isolado com `TestServer` (doc "Test ASP.NET Core middleware")
Pacote `Microsoft.AspNetCore.TestHost`. Monta um pipeline só com o que quer testar: `UseTestServer()`, `ConfigureServices`, `Configure(app => app.UseMiddleware<MyMiddleware>())`, `StartAsync()`; envie requests com `host.GetTestClient()` (HttpClient) ou `server.SendAsync(ctx => ...)` para manipular `HttpContext` diretamente (`Items`, `Features`). Vantagens: requests em memória (sem portas/certificados HTTPS), exceções do middleware voltam direto ao teste. Rotas extras: `UseRouting` + `UseEndpoints(MapGet(...))`. Dica da doc: escreva primeiro um assert **oposto** ao esperado para confirmar que o teste falha, depois ajuste ao correto (evita falso positivo).

## Minimal APIs: unit + integration (doc "Unit and integration tests in Minimal API apps")
Handlers como **métodos nomeados** (não lambdas) podem ser unit-testados chamando o método e conferindo o tipo concreto do `TypedResults` (`Ok<T>`, `NotFound`, `Created<T>`); se o endpoint retorna vários tipos (`Results<NotFound, Ok<Todo>>`), converta o resultado para o tipo concreto esperado; se retorna um só, o tipo é inferido. A integração usa `WebApplicationFactory` como acima.

## SPAs e UI
Para SPAs a doc recomenda **Playwright for .NET** (automatiza navegador). Teste de carga: ver `dotnet-test-automation`.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Projeto de integração separado dos unitários; referencia `Microsoft.AspNetCore.Mvc.Testing`, SDK Web |
| 2 | Usa `WebApplicationFactory`, não sobe servidor manual/porta fixa |
| 3 | Fixture compartilhado por classe (`IClassFixture`); recursos descartados |
| 4 | Banco de teste real (ou estratégia justificada), isolado do banco de desenvolvimento/produção |
| 5 | Serviços externos substituídos via `ConfigureTestServices`/`WithWebHostBuilder` |
| 6 | Auth com handler de teste e esquema correto; casos autenticado e não autenticado |
| 7 | Asserts de status code, headers (`Location`, `Content-Type`) e corpo (DTO), não só `EnsureSuccessStatusCode` |
| 8 | Dados semeados de forma determinística; testes independentes entre si e entre execuções paralelas |
| 9 | Foco em cenários de infraestrutura; sem permutações exaustivas (essas ficam em unitários) |
| 10 | `args` passados ao `CreateBuilder` se usar `ConfigureHostConfiguration` |
| 11 | Ambiente de teste definido explicitamente |
| 12 | Nenhum segredo/connection string de produção em testes |

## Fontes oficiais
- Integration tests in ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests
- Testing in .NET (tipos de teste): https://learn.microsoft.com/en-us/dotnet/core/testing/
- Unit testing best practices (terminologia fake/mock/stub): https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices
- Testing EF Core applications: https://learn.microsoft.com/en-us/ef/core/testing/
- Playwright for .NET (SPAs): https://playwright.dev/dotnet/

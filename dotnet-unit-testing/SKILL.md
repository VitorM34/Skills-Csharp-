---
name: dotnet-unit-testing
description: Escrever e revisar testes unitários em .NET (xUnit/MSTest/NUnit) - [Fact]/[Theory]/[InlineData], Arrange-Act-Assert, nomenclatura Método_Cenário_Resultado, TDD, stubs/mocks/fakes, isolamento de dependências, seams para DateTime, testar métodos privados, setup vs helpers, cobertura. Use quando o usuário pedir para criar testes unitários, revisar se estão bons ou tornar código testável. Based on official Microsoft Learn docs.
---

# Testes unitários em .NET — escrever e revisar

Só afirmar o que a doc oficial diz (fontes no fim). Visão geral/estratégia/CLI/cobertura: `dotnet-test-automation`. API ASP.NET Core ponta a ponta: `dotnet-integration-testing`. Dados com EF Core: `efcore-testing`.

## O que é um teste unitário (doc)
Exercita um componente/método individual ("unit of work"); **só código sob seu controle**. **Não testa infraestrutura** (banco, arquivos, rede): isso é integração. Benefícios: menos teste funcional manual (ms vs. minutos), proteção contra regressão, documentação executável, código menos acoplado.

## Características de um bom teste
**Fast** (milissegundos), **Isolated** (sem dependências externas como file system/banco), **Repeatable** (mesmo resultado sempre), **Self-checking** (decide passou/falhou sozinho), **Timely** (se testar custa desproporcionalmente mais que escrever o código, repense o design).

## Preparar o projeto (tutorial oficial xUnit)
```bash
dotnet new sln -o MySolution && cd MySolution
dotnet new classlib -o PrimeService
dotnet new xunit -o PrimeService.Tests          # já traz Microsoft.NET.Test.Sdk, xunit, xunit.runner.visualstudio, coverlet.collector
dotnet sln add ./PrimeService/PrimeService.csproj ./PrimeService.Tests/PrimeService.Tests.csproj
dotnet add ./PrimeService.Tests/PrimeService.Tests.csproj reference ./PrimeService/PrimeService.csproj
dotnet test
```
Frameworks suportados: xUnit.net, MSTest, NUnit, TUnit (ver `dotnet-test-automation`). Siga o framework já usado na solution.

## Como escrever
```csharp
public class PrimeService_IsPrimeShould                 // classe: Classe_MétodoShould (estilo do tutorial)
{
    private readonly PrimeService _primeService = new();

    [Theory]
    [InlineData(-1)]
    [InlineData(0)]
    [InlineData(1)]
    public void IsPrime_ValuesLessThan2_ReturnFalse(int value)   // Método_Cenário_Resultado
    {
        // Arrange (aqui o objeto sob teste já criado)
        // Act
        var result = _primeService.IsPrime(value);

        // Assert
        Assert.False(result, $"{value} should not be prime");
    }
}
```
- **`[Fact]`** = teste único. **`[Theory]` + `[InlineData]`** = mesmos passos com entradas diferentes; **não copie** o teste só para mudar um parâmetro.
- **TDD** (citado pela doc): escreva um teste que falha, escreva só o código necessário para passar, repita (red → green → próximo).

## Boas práticas (doc "Unit testing best practices")
1. **Sem dependências de infraestrutura:** aplique Explicit Dependencies + DI; mantenha testes unitários e de integração em **projetos separados** (o projeto unitário nem referencia pacotes de infra).
2. **Nome em 3 partes:** método testado + cenário + comportamento esperado (`Add_SingleNumber_ReturnsSameNumber`; `Test_Single` é ruim). Os testes funcionam como documentação.
3. **Arrange / Act / Assert** explícitos; um único Act; legibilidade acima de tudo.
4. **Teste minimamente passante:** a entrada mais simples que verifica o comportamento; sem propriedades extras no modelo.
5. **Sem magic strings:** `const string MAXIMUM_RESULT = "1001";`.
6. **Sem lógica no teste** (`if/for/while/switch`, concatenação manual): use `[Theory]` ou divida.
7. **Helpers em vez de Setup/Teardown** (`CreateDefaultStringCalculator()`): tudo visível no teste, menos estado compartilhado. (`SetUp/TearDown` não existem no xUnit 2.x+; no xUnit use o construtor se precisar, com cuidado.)
8. **Não teste métodos privados:** teste o método público que os usa (o resultado público é o que importa).
9. **Seams para estáticos** (`DateTime.Now`, relógio, aleatório): encapsule em interface injetável (a doc usa `IDateTimeProvider`) e controle o valor no teste. Sem seam o teste passa/falha conforme o dia da semana.
10. **Cobertura:** alta cobertura não indica qualidade; metas ambiciosas (95%) são contraproducentes.

## Terminologia (doc): fake, stub, mock
- **Fake:** termo genérico (pode atuar como stub ou mock). **Stub:** substituto controlável de uma dependência, **sem** assert nele. **Mock:** fake sobre o qual se faz `Assert` (decide se o teste passa).
- Nomeie conforme o papel (`FakeOrder`, `stubOrder`, `mockOrder`); chamar stub de "mock" induz a erro. A literatura clássica (Fowler, Meszaros) usa os termos de forma mais estrita; a doc avisa que o uso varia.
- Mock = stub + `Assert` nele. Se não há `Assert` no objeto, é stub.


## Controllers, Razor Pages e Minimal APIs (doc ASP.NET Core)
- **Controller (unit):** teste só o **conteúdo de uma action**, não filtros, rotas nem model binding (isso é integração). O controller segue o Explicit Dependencies Principle e recebe `IRepository` por DI: use mock/stub do repositório. Assert no tipo do resultado (`ViewResult`, `RedirectToActionResult`, `NotFoundObjectResult`, `BadRequestObjectResult`) e no modelo retornado. Para `ModelState` inválido, **adicione o erro** (`ModelState.AddModelError`) em vez de passar um modelo inválido (o binding não roda no unit test). Um teste por cada `return`/ramo da action. Mocks verificáveis (`Verify`) para checar que o repositório foi chamado (Moq é usado no sample; é biblioteca de terceiros).
- **Não retorne entidades de domínio** direto da API (carregam mais dados que o necessário e acoplam o modelo interno ao contrato público); mapeie para DTO manualmente (LINQ `Select`) ou com biblioteca (ex.: AutoMapper). Ver `dotnet-dto-review`.
- **Razor Pages:** testes unitários de DAL e de page models; métodos do DAL `virtual` permitem mock; para banco "novo" a cada teste crie `DbContextOptions` com um novo service provider/nome de banco (senão um teste herda o estado do anterior). A doc de Razor Pages usa InMemory no exemplo, mas a doc de EF Core desencoraja (ver `efcore-testing`).
- **Minimal API:** handlers como métodos nomeados retornam `TypedResults`; assert no tipo concreto (`Ok<T>`, `NotFound`).
- Filtros e rotas customizados: teste-os **isoladamente**, não via uma action específica.

## O que NÃO é unitário (não force)
Banco real, `WebApplicationFactory`, HTTP real, sistema de arquivos: vão para `dotnet-integration-testing`/`efcore-testing`. Mockar `DbSet` para testar consulta é desencorajado (ver `efcore-testing`); prefira um repositório stubado ou teste de integração com banco.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Teste unitário toca banco/arquivo/rede/relógio real | Alta |
| 2 | Teste depende de ordem, de estado compartilhado ou de execuções anteriores | Alta |
| 3 | Sem Assert (ou Assert trivial) / assert na coisa errada | Alta |
| 4 | Nome não segue Método_Cenário_Resultado | Média |
| 5 | AAA ausente/misturado; vários Act | Média |
| 6 | Lógica (`if/for`) ou loop de casos dentro do teste → `[Theory]` | Média |
| 7 | Casos copiados em vez de `[InlineData]` | Média |
| 8 | Teste de método privado | Média |
| 9 | Código sob teste acoplado a estático (`DateTime.Now`, `new` de colaborador) sem seam/DI | Média |
| 10 | Magic strings/números; dados excessivos no arrange | Baixa |
| 11 | Setup compartilhado escondendo pré-condições | Baixa |
| 12 | Stub chamado de mock (ou o contrário) | Baixa |
| 13 | Cobertura usada como única meta | Baixa |

## Fontes oficiais
- Unit testing best practices: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices
- Testing in .NET: https://learn.microsoft.com/en-us/dotnet/core/testing/
- Tutorial xUnit com `dotnet test`: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-csharp-with-xunit
- Código sob teste e cobertura: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-code-coverage
- xUnit.net: https://xunit.net

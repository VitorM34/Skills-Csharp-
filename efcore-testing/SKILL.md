---
name: efcore-testing
description: Escolher e implementar estratégia de testes para código que usa EF Core - testar contra o banco real de produção, SQLite in-memory, provider InMemory, mock de DbContext/DbSet, repository pattern, isolamento de dados com transações, fixtures xUnit, Testcontainers, limpeza de banco. Use quando o usuário perguntar como testar o acesso a dados, se pode usar InMemory, ou revisar testes que envolvem DbContext. Based on official Microsoft Learn docs (EF Core).
---

# Testes com EF Core — escolher a estratégia e isolar dados

Só afirmar o que a doc oficial diz (fontes no fim). Integração de API: `dotnet-integration-testing`. Unitários: `dotnet-unit-testing`.

## Recomendação oficial (resumo da doc)
1. **Tenha boa cobertura rodando contra o seu banco de produção real.** É necessário de qualquer forma e dá confiança de que funciona em produção. Comece por aí; adicione test doubles depois, se precisar.
2. Se usar test double, **implemente o repository pattern** (stub/mock da camada acima do EF Core) em vez de provider falso ou mock de `DbSet`.
3. Se o repository não for viável, **SQLite in-memory**.
4. **Evite o provider InMemory** ("altamente desencorajado", suportado só para apps legados).
5. **Evite mockar `DbSet` para consultas.**

## Por que testar com banco real é mais fácil do que parece (doc)
- Bancos instalam fácil: **Docker** e **Testcontainers** (gerencia o ciclo de vida de bancos em contêiner nos testes); Dev Containers/Codespaces.
- Banco local com dataset razoável é **muito rápido** (o EF Core roda 30.000+ testes contra SQL Server em poucos minutos, em CI a cada commit). Usar InMemory "por velocidade" quase nunca se justifica.
- O difícil é **isolamento** (testes alterando dados e interferindo): há técnicas (abaixo).
- Test doubles são necessários para o que não se testa de outro modo (ex.: simular falha de banco).
- Um double passar não garante que funciona em produção (ex.: SQLite compara strings com case-sensitivity; SQL Server por padrão não).

## Comparativo (doc)
| | InMemory | SQLite in-memory | Mock DbContext | Repository | Banco real |
|---|---|---|---|---|---|
| Tipo | Fake | Fake | Fake | Mock/stub | Real |
| SQL bruto | Não | Depende | Não | Sim | Sim |
| Transações | Não (ignoradas) | Sim | Sim | Sim | Sim |
| Funções específicas do provider | Não | Não | Não | Sim | Sim |
| Comportamento exato das queries | Depende | Depende | Depende | Sim | Sim |
- **SQLite:** providers diferem (EF não abstrai tudo); mesma LINQ pode dar resultado diferente; `EF.Functions.DateDiffDay` do SQL Server falha; SQL bruto pode divergir.
- **InMemory:** além dos problemas do SQLite, suporta menos queries, **sem transações**, **sem SQL bruto**, e é mais lento que SQLite in-memory.
- **Mock de `DbContext`:** bom para funcionalidade **não-query** (verificar chamadas a `Add`/`SaveChanges`). Mockar a consulta do `DbSet` não é possível de verdade (LINQ são extension methods estáticos sobre `IQueryable`); o que se faz é um `DbSet` sobre coleção em memória = fake com os mesmos defeitos do InMemory.
- **Repository:** o repository de produção contém as queries LINQ; nos testes é stubado, retirando o EF Core da pilha. Custo: camada arquitetural extra, e o repositório **não pode expor `IQueryable`** (queries testáveis devem ficar em métodos que retornam `IEnumerable`). Você ainda precisa de testes contra o banco real para as queries do repositório.

## Testando contra o banco real (doc "Testing against your production database system")
1. **Instalar:** pacote do banco, Docker em CI, Testcontainers. SQL Server: prefira **Developer Edition** a LocalDB (LocalDB: nem tudo do SQL Server, só Windows, lag no 1º teste). Cloud: teste contra versão local (SQL Azure → SQL Server local; Cosmos DB → emulador), mas rode também contra o serviço antes de produção.
2. **Criar/semear uma vez** com **class fixture** do xUnit: `EnsureDeleted()` + `EnsureCreated()` e seed; use lock + flag para criar uma vez quando o fixture é usado por várias classes (collection fixture impediria paralelismo). Pense bem no seed: mudar depois pode quebrar testes.
3. **Testes só de leitura:** sem interferência; basta `CreateContext()` do fixture.
4. **Testes que alteram dados:** envolva em **transação** que nunca é commitada (rollback implícito ao descartar o contexto). Chame `ChangeTracker.Clear()` antes de reler para realmente buscar do banco. Dica: inicie a transação dentro do `CreateContext()` do fixture para não esquecer; separe classes de leitura e de escrita.
5. **Testes que gerenciam transações explicitamente** (sem transação aninhada): limpe o banco após cada teste (`Cleanup`) e **desabilite paralelismo** entre eles: use **collection fixture** com collection definition; um banco/fixture próprio. Quer paralelismo? Use fixtures diferentes, cada um com seu banco (criar vários bancos de teste não é problema).
6. **Criação eficiente:** `EnsureDeleted/EnsureCreated` podem ser lentos; temporariamente comentar `EnsureDeleted` reaproveita o banco, mas o schema pode ficar desatualizado se o modelo mudar (só durante o ciclo de desenvolvimento).
7. **Limpeza eficiente:** `DELETE FROM [Tabela];` bruto, ou o pacote **Respawn**, que limpa sem listar tabelas.
8. A doc mostra xUnit, mas "conceitos similares existem em NUnit e outros".

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Existem testes contra o provider real (SQL Server/PostgreSQL/…) para queries e migrations |
| 2 | Uso de `UseInMemoryDatabase` como substituto de banco → recomendar banco real/SQLite/repository |
| 3 | `Mock<DbSet<T>>` usado para testar consultas |
| 4 | Testes de escrita isolados (transação com rollback ou limpeza) |
| 5 | Banco criado/semeado uma vez por fixture, thread-safe |
| 6 | Testes que usam transação explícita sem paralelismo e com cleanup |
| 7 | `ChangeTracker.Clear()` antes de reler após alterar |
| 8 | Dados de seed estáveis e documentados |
| 9 | Banco de teste separado do de desenvolvimento; connection string de teste própria |
| 10 | Repositório não expõe `IQueryable` quando for mockado |
| 11 | CI com contêiner (Docker/Testcontainers) para o banco |

## Fontes oficiais
- Testing EF Core applications (visão geral): https://learn.microsoft.com/en-us/ef/core/testing/
- Choosing a testing strategy: https://learn.microsoft.com/en-us/ef/core/testing/choosing-a-testing-strategy
- Testing against your production database system: https://learn.microsoft.com/en-us/ef/core/testing/testing-with-the-database
- Testing without your production database system: https://learn.microsoft.com/en-us/ef/core/testing/testing-without-the-database
- Testcontainers para .NET: https://dotnet.testcontainers.org/

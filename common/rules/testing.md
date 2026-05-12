---
description: Detroit-style unit tests — InMemory ports, UnitTest base, AssertK, Given-When-Then, explicit timestamps for Kotlin/JVM.
alwaysApply: true
---

# Testing Strategy - Unit Tests

## Testing Philosophy

We follow the **Detroit (Classical) style** of Test-Driven Development, not the London (Mockist) style.

### Detroit Style Principles
- Test behavior, not implementation
- Use real objects whenever possible
- Only use test doubles for external dependencies (databases, HTTP clients, message queues)
- Tests should survive refactoring - changing internal structure shouldn't break tests
- Test the system through its public API

### Why Not London Style?
- Mocks couple tests to implementation details
- Tests become brittle and break during refactoring
- Over-mocking leads to tests that pass but production code fails
- Mock-heavy tests are harder to read and maintain

## Test Doubles Strategy

### Prefer InMemory Implementations Over Mocks

**DO NOT** use mocking frameworks (Mockito, MockK) for repositories and internal services.

**DO** create InMemory implementations backed by `MutableMap` or `MutableList`:

```kotlin
// Port in application layer
interface UserRepository {
    fun findById(id: UserId): User?
    fun save(user: User)
}

// InMemory implementation in test sources
class InMemoryUserRepository : UserRepository {
    private val store = mutableMapOf<UserId, User>()
    
    override fun findById(id: UserId): User? = store[id]
    
    override fun save(user: User) {
        store[user.id] = user
    }
    
    // Test helper methods
    fun clear() = store.clear()
}
```

### When to Use Fakes vs Real Implementations

| Dependency Type | Strategy |
|-----------------|----------|
| Domain objects | Use real objects |
| Application services | Use real objects |
| Repositories (ports) | Use InMemory implementations |
| External HTTP clients | Use Fakes that return predefined responses |
| Time | Use `FixedTimeProvider` with `configure()` method |
| Random/UUID generators | Use deterministic implementation |

## Test Structure

### Abstract UnitTest Base Class

All unit tests must inherit from an abstract `UnitTest` class that provides pre-wired dependencies:

```kotlin
abstract class UnitTest {

    // Test utilities
    val builders = Builders()
    val timeProvider = FixedTimeProvider()
    
    // Repositories (InMemory implementations)
    val userRepository = InMemoryUserRepository()
    val orderRepository = InMemoryOrderRepository()
    
    // Domain services (real implementations)
    val userFacade = UserFacade(userRepository)
    val orderFacade = OrderFacade(orderRepository, userFacade)
    
    // Application services (real implementations)
    val userService = UserService(userFacade)
    val orderService = OrderService(orderFacade, userService)
}
```

**Rules for UnitTest class:**
- Add every new repository as an InMemory implementation
- Wire real implementations of domain and application services
- Keep dependencies in logical order (repositories → domain → application)
- Provide `Builders` instance for creating test objects
- Provide `FixedTimeProvider` for time-dependent tests

### Builders for Domain Objects

Create a `Builders` class that provides factory methods for creating domain objects with sensible defaults:

```kotlin
class Builders {
    
    fun aUser(
        id: UserId = UserId("user-123"),
        name: String = "John Doe",
        email: Email = Email("john@example.com"),
        status: UserStatus = UserStatus.ACTIVE
    ): User = User(
        id = id,
        name = name,
        email = email,
        status = status
    )
    
    fun anOrder(
        id: OrderId = OrderId("order-456"),
        userId: UserId = UserId("user-123"),
        items: List<OrderItem> = listOf(anOrderItem()),
        status: OrderStatus = OrderStatus.PENDING
    ): Order = Order(
        id = id,
        userId = userId,
        items = items,
        status = status
    )
    
    fun aWatchEvent(
        timestamp: String = "2025-11-11T20:41:26.993Z",
        title: String = "Some Title"
    ): WatchEvent = WatchEvent(
        timestamp = Instant.parse(timestamp),
        title = title
    )
}
```

**Rules for Builders:**
- Provide sensible defaults for all parameters
- Use named parameters for clarity
- Nest builders for complex object graphs
- Keep builder methods simple - just object construction
- Use `String` for timestamps (ISO-8601 format) - more readable than `Instant`

## Test Organization

### Test Location

All test files reside in `src/test/kotlin/`:

```
src/test/kotlin/
├── UnitTest.kt                    # Abstract base class
├── common/
│   ├── Builders.kt                # Test object builders
│   ├── inmemory/                  # InMemory implementations (test doubles)
│   │   ├── InMemoryUserRepository.kt
│   │   └── InMemoryOrderRepository.kt
│   └── assertion/                 # Custom assertions
│       ├── assertions.kt          # Common assertion helpers
│       ├── userAssertions.kt      # User-related assertions
│       └── repositoryAssertions.kt # Repository assertions
├── domain/
│   └── user/
│       └── UserFacadeTest.kt      # Tests for UserFacade
└── application/
    └── user/
        └── UserServiceTest.kt     # Tests for UserService
```

### Test Class Structure

```kotlin
class UserFacadeTest : UnitTest() {
    
    @Test
    fun `should find user by id`() {
        // given
        val user = builders.aUser(name = "Jane Doe")
        userRepository.save(user)
        
        // when
        val result = userFacade.findById(user.id)
        
        // then
        assertThat(result?.name).isEqualTo("Jane Doe")
    }
    
    @Test
    fun `should return null when user not found`() {
        // when
        val result = userFacade.findById(UserId("non-existent"))
        
        // then
        assertThat(result).isNull()
    }
}
```

## Testing Guidelines

### What to Test

- **Domain logic** - all business rules, validations, calculations
- **Application services** - orchestration logic, use case flows
- **Edge cases** - boundary conditions, error scenarios
- **State changes** - verify that operations modify state correctly

### What NOT to Test

- Framework code (Spring, Jackson, etc.)
- Simple getters/setters
- Data classes without logic
- External libraries

### Testing Scope - Facades vs Services

**Domain Facades** - Test comprehensively:
- Facades are the main entry point to domain logic
- Test all business rules, validations, and edge cases
- These tests should cover the core domain behavior

**Application Services** - Test use case orchestration:
- Focus on the flow and coordination between facades
- Don't duplicate facade tests - assume domain logic works
- Test application-specific concerns (transactions, events, etc.)

```kotlin
// Domain Facade Test - comprehensive business logic testing
class UserFacadeTest : UnitTest() {
    @Test
    fun `should validate email format`() { /* ... */ }
    
    @Test
    fun `should prevent duplicate emails`() { /* ... */ }
}

// Application Service Test - use case orchestration
class CreateUserUseCaseTest : UnitTest() {
    @Test
    fun `should create user and send welcome email`() { /* ... */ }
}
```

### Test Naming Convention

Use backtick syntax with descriptive sentences:

```kotlin
@Test
fun `should calculate total price including tax`() { }

@Test
fun `should throw exception when user not found`() { }

@Test
fun `should send notification after order completion`() { }
```

### Testing Exceptions

Use AssertK's `assertFailure` for testing exceptions:

```kotlin
@Test
fun `should throw exception when user not found`() {
    // when/then
    assertFailure { userFacade.getOrThrow(UserId("non-existent")) }
        .isInstanceOf<UserNotFoundException>()
        .hasMessage("User not found: non-existent")
}
```

For result types that don't throw, use custom assertions:

```kotlin
@Test
fun `should return failure when email already exists`() {
    // given
    userRepository.save(builders.aUser(email = Email("taken@example.com")))
    
    // when
    val result = userFacade.create(builders.aUser(email = Email("taken@example.com")))
    
    // then
    assertThat(result).isFailure()
}
```

### Given-When-Then Structure

Every test should follow the Given-When-Then pattern:

```kotlin
@Test
fun `should apply discount for premium users`() {
    // given - setup preconditions
    val premiumUser = builders.aUser(status = UserStatus.PREMIUM)
    userRepository.save(premiumUser)
    
    val order = builders.anOrder(userId = premiumUser.id)
    
    // when - execute the action
    val result = orderService.calculateTotal(order)
    
    // then - verify the outcome
    assertThat(result.discount).isEqualTo(Percentage(10))
}
```

**Rules for Given-When-Then:**
- Values verified in `then` must be explicitly passed in `given` - no "magic" values from builder defaults
- Use named arguments for clarity - no need for intermediate variables
- This makes tests self-documenting and prevents false positives when defaults change

```kotlin
// Bad - magic values from builder defaults
@Test
fun `should find user`() {
    // given
    userRepository.save(builders.aUser())
    
    // when
    val user = userFacade.findById(UserId("user-123"))
    
    // then
    assertThat(user?.name).isEqualTo("John Doe")  // Where does "John Doe" come from?
}

// Good - explicit values with named arguments
@Test
fun `should find user`() {
    // given
    val user = builders.aUser(id = UserId("user-123"), name = "Jane Doe")
    userRepository.save(user)
    
    // when
    val result = userFacade.findById(UserId("user-123"))
    
    // then
    assertThat(result?.name).isEqualTo("Jane Doe")  // Clear: same value as in given
}
```

## InMemory Implementation Patterns

### Basic Repository

```kotlin
class InMemoryUserRepository : UserRepository {
    private val store = mutableMapOf<UserId, User>()
    
    override fun findById(id: UserId): User? = store[id]
    override fun findAll(): List<User> = store.values.toList()
    override fun save(user: User) { store[user.id] = user }
    override fun delete(id: UserId) { store.remove(id) }
    
    // Test helpers
    fun clear() = store.clear()
    fun saveAll(vararg users: User) = users.forEach(::save)
}
```

## TimeProvider Pattern

### Production TimeProvider

In the domain layer, create a `@Component` that provides current time:

```kotlin
@Component
class TimeProvider {
    open fun now(): Instant = Instant.now()
}
```

### FixedTimeProvider for Tests

In test sources, create a controllable implementation:

```kotlin
class FixedTimeProvider(
    private var currentInstant: Instant = Instant.now()
) : TimeProvider() {

    override fun now(): Instant = currentInstant

    fun configure(now: Instant) {
        currentInstant = now
    }

    fun configure(now: String) {
        currentInstant = Instant.parse(now)
    }
}
```

### Usage in Tests

Use explicit ISO-8601 timestamps for readability:

```kotlin
@Test
fun `should filter events by time range`() {
    // given
    timeProvider.configure(now = "2025-12-18T12:00:00Z")
    watchEventRepository.saveAll(
        builders.aWatchEvent(timestamp = "2025-12-18T11:00:00Z", title = "Recent"),
        builders.aWatchEvent(timestamp = "2025-12-16T12:00:00Z", title = "Old")
    )

    // when
    val results = facade.findRecent(timeRange = "24h")

    // then
    assertThat(results).hasSize(1)
}
```

**Rules for time in tests:**
- Always use explicit ISO-8601 timestamps (e.g., `"2025-12-18T12:00:00Z"`)
- Avoid calculated timestamps like `now.minus(1, ChronoUnit.HOURS)` - they are harder to read
- Configure `timeProvider` at the beginning of each test that depends on time

## Assertions

Use AssertK for fluent, readable assertions:

```kotlin
// Good - fluent and readable
assertThat(user.name).isEqualTo("John")
assertThat(orders).hasSize(3)
assertThat(result).isInstanceOf<Success>()

// Avoid - less readable
assertEquals("John", user.name)
assertTrue(orders.size == 3)
```

### Custom Assertions

Create domain-specific custom assertions as extension functions on `Assert<T>`. This improves test readability and enables fluent chaining of assertions.

Organize custom assertions by domain concept:

```
common/assertion/
├── userAssertions.kt
├── orderAssertions.kt
├── repositoryAssertions.kt
└── contentAssertions.kt
```

#### Basic Custom Assertion

Use `given` when you want to perform an assertion and return `Unit`:

```kotlin
fun Assert<User>.hasName(expected: String): Unit = given { actual ->
    assertThat(actual.name).isEqualTo(expected)
}

fun Assert<User>.hasEmail(expected: String): Unit = given { actual ->
    assertThat(actual.email.value).isEqualTo(expected)
}
```

#### Transforming Assertion

Use `transform` when you want to extract a value and continue the assertion chain:

```kotlin
fun Assert<Order>.hasItem(productId: ProductId): Assert<OrderItem> = transform { actual ->
    actual.items.find { it.productId == productId } 
        ?: expected("to have item with productId=$productId")
}
```

#### Negative Assertions

```kotlin
fun Assert<UserRepository>.doesNotHaveUser(id: UserId): Unit = given { repository ->
    assertThat(repository.findById(id)).isNull()
}
```

#### Assertion Chaining with `that`

Create a helper extension for grouping multiple assertions:

```kotlin
fun <T> Assert<T>.that(body: Assert<T>.() -> Unit) = all(body)
```

Usage in tests:

```kotlin
@Test
fun `should find user with all properties`() {
    // given
    val user = builders.aUser(
        name = "Jane Doe", 
        email = Email("jane@example.com"),
        status = UserStatus.ACTIVE
    )
    userRepository.save(user)

    // when
    val foundUser = userFacade.findById(user.id)

    // then
    assertThat(foundUser).isNotNull()
    assertThat(foundUser!!).that {
        hasName("Jane Doe")
        hasEmail("jane@example.com")
        hasStatus(UserStatus.ACTIVE)
    }
}
```

#### Repository Assertions

Custom assertions for repositories make tests more expressive:

```kotlin
fun Assert<UserRepository>.hasUser(id: UserId): Assert<User> = transform { repository ->
    repository.findById(id) ?: expected("to have user with id=$id")
}

fun Assert<UserRepository>.hasSize(expected: Int): Unit = given { repository ->
    assertThat(repository.findAll().size).isEqualTo(expected)
}

fun Assert<OrderRepository>.hasOrderForUser(userId: UserId): Assert<Order> = transform { repository ->
    repository.findByUserId(userId).firstOrNull() 
        ?: expected("to have order for userId=$userId")
}
```

Usage:

```kotlin
@Test
fun `should save user to repository`() {
    // given
    val user = builders.aUser(name = "Jane Doe")
    
    // when
    userFacade.save(user)
    
    // then
    assertThat(userRepository)
        .hasUser(user.id)
        .that {
            hasName("Jane Doe")
            hasStatus(UserStatus.ACTIVE)
        }
}
```

#### Result Type Assertions

For sealed classes and result types:

```kotlin
fun Assert<CreateUserResult>.isSuccess(): Assert<User> = transform { actual ->
    when (actual) {
        is CreateUserResult.Success -> actual.user
        else -> expected("success but was $actual")
    }
}

fun Assert<CreateUserResult>.isFailure(): Unit = given { actual ->
    if (actual !is CreateUserResult.Failure) {
        expected("failure but was $actual")
    }
}
```

**Rules for Custom Assertions:**
- Use `given` for terminal assertions (returns `Unit`)
- Use `transform` for chainable assertions (returns `Assert<T>`)
- Use `expected()` to provide clear error messages
- Group assertions by domain concept in separate files
- Prefer specific assertions over generic ones

## Summary

| Principle | Practice |
|-----------|----------|
| Test style | Detroit (Classical) |
| Mocking | Avoid - use InMemory implementations |
| Test inheritance | Extend `UnitTest` base class |
| Object creation | Use `Builders` class with String timestamps |
| Time handling | Use `FixedTimeProvider` with explicit ISO-8601 timestamps |
| Test structure | Given-When-Then |
| Naming | Backtick with descriptive sentences |
| Assertions | AssertK with custom domain assertions |
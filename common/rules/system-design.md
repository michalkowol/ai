---
description: Hexagonal architecture — boundary, application, domain layers and inward dependency flow for Paramount compas codebases.
alwaysApply: true
---

# System Design - Hexagonal Architecture

## Package Structure

All code must be organized into three main subpackages:

```
tech.paramount.compas/
├── boundary/    # External interfaces (adapters, controllers, clients)
├── application/ # Facades and application services
└── domain/      # Core business logic, entities, and ports
```

### Package Responsibilities

**`domain`** - The innermost layer
- Contains entities (aggregates, value objects)
- Contains domain services - pure business logic that doesn't fit any entity
- Contains ports (interfaces) - e.g., `UserRepository`, `PaymentGateway`
- Contains domain events
- Has no dependencies on other layers
- Pure business rules - no knowledge of how it's called or technical details (transactions, security, etc.)
- Can only import from `domain`

**`application`** - The middle layer  
- Contains **Facades / Application Services** - orchestration of use cases
- Contains DTOs for communication between layers
- Manages transactions (`@Transactional`)
- Can import from `application` and `domain`
- Cannot import from `boundary`

**`boundary`** - The outermost layer
- **Inbound adapters**: REST controllers, message listeners, schedulers
- **Outbound adapters**: repository implementations, HTTP clients, external integrations
- Implements ports defined in `domain`
- Handles all external communication (HTTP, DB, messaging, etc.)
- Can import from `boundary`, `application`, and `domain`

## Dependency Flow

Dependencies must always flow **inward**:

```
boundary → application → domain
```

| From Layer    | Can Access                          |
|---------------|-------------------------------------|
| `domain`      | `domain` only                       |
| `application` | `application`, `domain`             |
| `boundary`    | `boundary`, `application`, `domain` |

**Never** create dependencies that flow outward (e.g., `domain` → `application`).

## Layer Summary

| Layer         | Contains                                          | Responsibility                              |
|---------------|---------------------------------------------------|---------------------------------------------|
| `domain`      | Entities, domain services, ports (interfaces)     | Business rules                              |
| `application` | Facades, DTOs                                     | Orchestration, transactions, mapping        |
| `boundary`    | Controllers, port implementations                 | Communication with external world           |

**Facades in `application` are "glue code"** - they connect domain with infrastructure, but the business logic itself remains in `domain`. This keeps the domain clean, testable, and framework-independent.

## Design Principles

### Simplicity First
- Prefer simple, straightforward solutions over clever abstractions
- Write code that is easy to read and understand
- Avoid premature optimization

### Rule of Three
- Do not create an abstraction until the same code pattern appears **three times**
- When reusing code: copy it once, and only abstract the third time
- Duplication in two places is acceptable and often preferable to premature abstraction

**Why this matters:**
- It's easier to make a good abstraction from duplicated code than to refactor the wrong abstraction
- Bad abstractions are either too specific (written without enough use cases) or needlessly generic (trying to cover too many hypothetical cases)
- Bad abstractions are the hardest quality problems to detect - they can have 100% test coverage and only break when you try to change something that depends on them
- The urge to create reusable components too early leads to confusion about where new code should go, making every change involve more work than expected

**Accept some duplication** - it adds a maintenance burden, but it's far better than the cost of maintaining and extending the wrong abstraction.

### No Unnecessary Abstractions
- Don't create interfaces unless there's a concrete need for multiple implementations
- Don't create factory classes for simple object creation
- Don't wrap framework classes just for the sake of "clean architecture"

*Exception: Ports in the domain layer are acceptable even with a single implementation, as they enable dependency inversion and testability.*

### Extensibility Through Simplicity
- Simple code is easier to extend than over-engineered code
- When in doubt, choose the simpler approach
- Let patterns emerge from real requirements, not hypothetical ones

## Code Organization Within Packages

Within each package, organize by feature/domain concept rather than by technical type:

```
domain/
├── user/
│   ├── User.kt                # entity
│   ├── UserRepository.kt      # port (interface)
│   └── UserPricingService.kt  # domain service (pure logic)
└── order/
    ├── Order.kt
    ├── OrderItem.kt
    └── OrderRepository.kt     # port (interface)

application/
├── user/
│   └── UserFacade.kt          # orchestration, @Transactional
└── order/
    └── OrderFacade.kt         # orchestration, @Transactional

boundary/
├── inbound/
│   ├── user/
│   │   └── UserController.kt
│   └── order/
│       └── OrderController.kt
└── outbound/
    ├── user/
    │   └── JpaUserRepository.kt    # implements UserRepository port
    └── order/
        └── JpaOrderRepository.kt   # implements OrderRepository port
```

## Facade Example

```kotlin
@Service
class OrderFacade(
    private val orderRepository: OrderRepository,      // port from domain
    private val paymentGateway: PaymentGateway,        // port from domain
    private val pricingService: PricingService,        // domain service
    private val eventPublisher: ApplicationEventPublisher
) {
    @Transactional
    fun placeOrder(command: PlaceOrderCommand): OrderDto {
        // Orchestration - combines different domain elements
        val order = Order.create(command.customerId, command.items)
        
        val finalPrice = pricingService.calculatePrice(order)
        order.setPrice(finalPrice)
        
        paymentGateway.charge(command.paymentDetails, finalPrice)
        
        val saved = orderRepository.save(order)
        eventPublisher.publishEvent(OrderPlacedEvent(saved.id))
        
        return OrderDto.from(saved)
    }
}
```
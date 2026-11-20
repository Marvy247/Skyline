# <Feature> — Specification

> A spec is written **before** the code, and updated **with** it. If this document and the
> implementation disagree, one of them is a bug.
>
> Delete the guidance in this blockquote when you use the template.

---

## 1. What it does

<One sentence.>

---

## 2. Why it exists

<The problem, in two or three sentences. Name the actor who is disadvantaged and by how much.>

---

## 3. Threat model boundary

**What this defends against:**

- <adversary> can <capability>

**What this does NOT defend against:**

- <explicitly out of scope>

> Be precise. Over-claiming here is the fastest way to lose a judge's trust.

---

## 4. Mechanism

### 4.1 The rule

```solidity
<the actual code, or the actual algorithm>
```

### 4.2 State it reads

| Source | Field | Meaning |
|---|---|---|
| <contract> | <field> | <meaning> |

### 4.3 State it writes

| Contract | Field | Meaning |
|---|---|---|
| | | |

### 4.4 Worked example

| Step | Action | Result |
|---|---|---|
| 1 | | |
| 2 | | |

---

## 5. Invariants

| ID | Statement | Test |
|---|---|---|
| INV-x | | `test/invariant/<Name>.t.sol` |

---

## 6. Interfaces

```solidity
function <name>(<args>) external returns (<ret>);
```

### Errors

| Error | When | Decoded message |
|---|---|---|
| | | |

### Events

| Event | Emitted when |
|---|---|
| | |

---

## 7. Gas

| Operation | Target | Actual |
|---|---|---|
| | | |

---

## 8. Edge cases

| Case | Handling |
|---|---|
| | |

---

## 9. Acceptance criteria

- [ ] <criterion>
- [ ] <criterion>

---

## 10. Open questions

- [ ] <question> — <owner> — <deadline>

---

*Related: `docs/03-ARCHITECTURE.md` · `docs/04-ECONOMICS.md` · `docs/05-SECURITY.md`*

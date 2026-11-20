// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title <ContractName>
 * @notice <One sentence: what this contract is and what it is responsible for.>
 * @dev <The non-obvious design constraint that a future reader must not break.>
 *
 * Responsibilities:
 *   - <responsibility>
 *   - <responsibility>
 *
 * Explicitly NOT responsible for:
 *   - <thing, and where it lives instead>
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract <ContractName> is ReentrancyGuard {
    /* ------------------------------------------------------------------ */
    /*                              Types                                 */
    /* ------------------------------------------------------------------ */

    struct <Thing> {
        // field: type — comment
    }

    enum Status {
        None,
        Active,
        Closed
    }

    /* ------------------------------------------------------------------ */
    /*                             Storage                               */
    /* ------------------------------------------------------------------ */

    address public immutable owner;
    IERC20 public immutable asset;

    mapping(bytes32 => <Thing>) public things;

    uint256 public counter;

    /* ------------------------------------------------------------------ */
    /*                              Events                                */
    /* ------------------------------------------------------------------ */

    event ThingCreated(bytes32 indexed id, address indexed creator, uint256 amount);
    event ThingUpdated(bytes32 indexed id, uint256 newAmount);

    /* ------------------------------------------------------------------ */
    /*                             Errors                                */
    /* ------------------------------------------------------------------ */

    error NotOwner();
    error NotRegistered();
    error ZeroAmount();
    error AlreadyExists();
    error InvalidAmount(uint256 amount);

    /* ------------------------------------------------------------------ */
    /*                            Modifiers                              */
    /* ------------------------------------------------------------------ */

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /* ------------------------------------------------------------------ */
    /*                           Construction                             */
    /* ------------------------------------------------------------------ */

    constructor(IERC20 asset_, address owner_) {
        asset = asset_;
        owner = owner_;
    }

    /* ------------------------------------------------------------------ */
    /*                             External                               */
    /* ------------------------------------------------------------------ */

    /// @notice Creates a thing.
    /// @dev <constraints, and why they exist>
    /// @param id The identifier.
    /// @param amount The amount, in asset units.
    /// @return ok True on success.
    function create(bytes32 id, uint256 amount) external onlyOwner returns (bool ok) {
        if (amount == 0) revert ZeroAmount();
        if (things[id].status != Status.None) revert AlreadyExists();

        things[id] = <Thing>({
            // ...
            status: Status.Active
        });

        counter++;
        emit ThingCreated(id, msg.sender, amount);
        return true;
    }

    /* ------------------------------------------------------------------ */
    /*                             Internal                               */
    /* ------------------------------------------------------------------ */

    /// @dev <helper, with the invariant it maintains>
    function _something() internal view returns (uint256) {
        return 0;
    }

    /* ------------------------------------------------------------------ */
    /*                               Views                                */
    /* ------------------------------------------------------------------ */

    /// @notice A view a third party can use to verify state independently.
    /// @dev <what it recomputes and from where>
    function verify(bytes32 id) external view returns (bool ok, uint256 derived, uint256 recorded) {
        return (true, 0, 0);
    }
}

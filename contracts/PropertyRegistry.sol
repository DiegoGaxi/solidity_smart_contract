// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * PropertyRegistry
 *
 * Workflow summary:
 * 1. Seller calls registerProperty(docHash, buyer, notary) => status PendingNotary.
 * 2. Notary validates and calls notaryApprove(propertyId) => status NotaryApproved.
 * 3. Buyer reviews & calls buyerApprove(propertyId) => status BuyerApproved.
 * 4. Government authorized account calls governmentSeal(propertyId) => status GovernmentSealed.
 * 5. Ownership considered finalized; optional transferOwnership can move seller role.
 *
 * Security & Integrity:
 * - Roles via OpenZeppelin AccessControl (NOTARY_ROLE, GOVERNMENT_ROLE).
 * - ReentrancyGuard in mutating functions.
 * - Document hash (docHash) is immutable; underlying dossier stored off-chain (e.g. IPFS CID hashed via keccak256).
 * - Each step enforces caller identity and status ordering.
 * - Seller can cancel before notary approval.
 */

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PropertyRegistry is AccessControl, ReentrancyGuard {
    bytes32 public constant NOTARY_ROLE = keccak256("NOTARY_ROLE");
    bytes32 public constant GOVERNMENT_ROLE = keccak256("GOVERNMENT_ROLE");

    enum Status {
        PendingNotary,
        NotaryApproved,
        BuyerApproved,
        GovernmentSealed,
        Completed,
        Cancelled
    }

    struct Property {
        uint256 id;
        address seller;
        address buyer;
        address notary;
        address government; // set at seal
        bytes32 docHash; // hash of metadata / dossier
        Status status;
        uint64 createdAt;
        uint64 updatedAt;
        bool buyerApproved;
        bool notaryApproved;
        bool governmentSealed;
    }

    uint256 private _counter;
    mapping(uint256 => Property) private _properties;

    // Indexes for quick lookup (optional expansions)
    mapping(address => uint256[]) public bySeller;
    mapping(address => uint256[]) public byBuyer;

    // Events
    event PropertyRegistered(uint256 indexed id, address indexed seller, address indexed buyer, address notary, bytes32 docHash);
    event NotaryApproved(uint256 indexed id, address indexed notary);
    event BuyerApproved(uint256 indexed id, address indexed buyer);
    event GovernmentSealed(uint256 indexed id, address indexed government);
    event OwnershipTransferred(uint256 indexed id, address indexed oldSeller, address indexed newSeller);
    event Cancelled(uint256 indexed id, address indexed seller);

    modifier onlyExisting(uint256 propertyId) {
        require(_properties[propertyId].id != 0, "Property: not found");
        _;
    }

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function registerProperty(bytes32 docHash, address buyer, address notary) external nonReentrant returns (uint256) {
        require(buyer != address(0) && notary != address(0), "Property: zero address");
        require(hasRole(NOTARY_ROLE, notary), "Property: notary not authorized");
        _counter++;
        uint256 id = _counter;
        Property storage p = _properties[id];
        p.id = id;
        p.seller = msg.sender;
        p.buyer = buyer;
        p.notary = notary;
        p.docHash = docHash;
        p.status = Status.PendingNotary;
        p.createdAt = uint64(block.timestamp);
        p.updatedAt = p.createdAt;
        bySeller[msg.sender].push(id);
        byBuyer[buyer].push(id);
        emit PropertyRegistered(id, msg.sender, buyer, notary, docHash);
        return id;
    }

    function notaryApprove(uint256 propertyId) external onlyExisting(propertyId) nonReentrant {
        Property storage p = _properties[propertyId];
        require(msg.sender == p.notary, "Property: caller not notary");
        require(p.status == Status.PendingNotary, "Property: wrong status");
        p.notaryApproved = true;
        p.status = Status.NotaryApproved;
        p.updatedAt = uint64(block.timestamp);
        emit NotaryApproved(propertyId, msg.sender);
    }

    function buyerApprove(uint256 propertyId) external onlyExisting(propertyId) nonReentrant {
        Property storage p = _properties[propertyId];
        require(msg.sender == p.buyer, "Property: caller not buyer");
        require(p.status == Status.NotaryApproved, "Property: waiting notary");
        p.buyerApproved = true;
        p.status = Status.BuyerApproved;
        p.updatedAt = uint64(block.timestamp);
        emit BuyerApproved(propertyId, msg.sender);
    }

    function governmentSeal(uint256 propertyId) external onlyExisting(propertyId) nonReentrant {
        Property storage p = _properties[propertyId];
        require(hasRole(GOVERNMENT_ROLE, msg.sender), "Property: caller not gov");
        require(p.status == Status.BuyerApproved, "Property: waiting buyer");
        p.government = msg.sender;
        p.governmentSealed = true;
        p.status = Status.GovernmentSealed;
        p.updatedAt = uint64(block.timestamp);
        emit GovernmentSealed(propertyId, msg.sender);
    }

    // Mark completed (optional separate finalization step)
    function markCompleted(uint256 propertyId) external onlyExisting(propertyId) nonReentrant {
        Property storage p = _properties[propertyId];
        require(p.status == Status.GovernmentSealed, "Property: not sealed");
        require(msg.sender == p.seller || msg.sender == p.buyer || hasRole(GOVERNMENT_ROLE, msg.sender), "Property: unauthorized");
        p.status = Status.Completed;
        p.updatedAt = uint64(block.timestamp);
    }

    function cancel(uint256 propertyId) external onlyExisting(propertyId) nonReentrant {
        Property storage p = _properties[propertyId];
        require(msg.sender == p.seller, "Property: caller not seller");
        require(p.status == Status.PendingNotary, "Property: cannot cancel now");
        p.status = Status.Cancelled;
        p.updatedAt = uint64(block.timestamp);
        emit Cancelled(propertyId, msg.sender);
    }

    function transferOwnership(uint256 propertyId, address newSeller) external onlyExisting(propertyId) nonReentrant {
        Property storage p = _properties[propertyId];
        require(msg.sender == p.seller, "Property: caller not seller");
        require(p.status == Status.GovernmentSealed || p.status == Status.Completed, "Property: not finalized");
        require(newSeller != address(0), "Property: zero address");
        address oldSeller = p.seller;
        p.seller = newSeller;
        p.updatedAt = uint64(block.timestamp);
        bySeller[newSeller].push(propertyId);
        emit OwnershipTransferred(propertyId, oldSeller, newSeller);
    }

    function getProperty(uint256 propertyId) external view onlyExisting(propertyId) returns (Property memory) {
        return _properties[propertyId];
    }

    function listBySeller(address seller) external view returns (uint256[] memory) { return bySeller[seller]; }
    function listByBuyer(address buyer) external view returns (uint256[] memory) { return byBuyer[buyer]; }
}

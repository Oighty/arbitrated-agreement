// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @author Oighty. Please contact me on Twitter (@oightytag) or Discord (Oighty #4287) if you have any questions about this contract.
 */

contract ArbitratedAgreement is ReentrancyGuard {
    //  -------------------- CONTRACT VARIABLES --------------------
    string public name; // Provides context to the users to which agreement this contract is for, may be a code word to maintain privacy

    address public supplier; // Address the entity supplying the good or service would like to receive payment at
    address public purchaser; // Address the entity purchasing the good or service would like to pay from
    address public multiSig;  // Address of a 2 of 2 GnosisSafe multisig wallet that the entities can use to agreeably take action
    address public arbitrator; // Address of a neutral third-party who will arbitrate resolution of the agreement, if required
    bool public active; // Whether or not the agreement is active (executed, but not yet completed).
    bool public inArbitration; // Whether or not the agreement is in arbitration
    bool public funded; // Whether or not the purchaser has funded the agreement

    uint private amount; // Amount that the purchaser is paying the supplier per the agreement
    bytes private docHash; // keccak256 hash of the agreement document. Hash provided instead of link to file to preserve privacy.

    //  -------------------- EVENTS --------------------------------
    event AgreementExecuted();
    event AgreementFunded();
    event AgreementModified();
    event AgreementCompleted();
    event AgreementCancelled();
    
    event ArbitrationRequested(address requestor);
    event ArbitrationCompleted();

    //  -------------------- CONSTRUCTOR FUNCTION ------------------
    constructor(
        string memory _name,
        address _supplier,
        address _purchaser,
        address _multiSig,
        address _arbitrator,
        bytes _docHash
    ) {
        name = _name;
        supplier = _supplier;
        purchaser = _purchaser;
        multisig = _multiSig;
        arbitrator = _arbitrator;
        amount = _amount;
        docHash = _docHash;
    }

    //  -------------------- MODIFIERS ----------------------------
    modifier onlyArbitrator {
        require(msg.sender == arbitrator);
        _;
    }

    modifier onlyMultiSig {
        require(tx.origin == multiSig);
        _;
    }

    modifier onlySupplier {
        require(msg.sender == supplier);
        _;
    }

    modifier onlyPurchaser {
        require(msg.sender == purchaser);
        _;
    }

    modifier onlyEntities {
        require(msg.sender == supplier || msg.sender == purchaser);
        _;
    }

    modifier allParticipants {
        require(msg.sender == arbitrator || msg.sender == supplier || msg.sender == purchaser);
        _;
    }

    modifier isActive {
        require(active);
        _;
    }

    modifier isNotActive {
        require(!active);
        _;
    }

    modifier isInArbitration {
        require(inArbitration);
        _;
    }

    //  -------------------- VIEW FUNCTIONS -----------------------
    
    function getAmount() external allParticipants view returns(uint) {
        return amount;
    }

    function getDocHash() external allParticipants view returns(bytes) {
        return docHash;
    }

    //  -------------------- ENTITY FUNCTIONS --------------------
    /**
     * @dev Called by the purchaser to fund the contract. Expects ether equivalent to the agreement amount to be sent.
     */
    function fund() external payable onlyPurchaser nonReentrant isActive {
        require(msg.value == amount);
        funded = true;
        emit AgreementFunded();
    }

    /**
     * @dev Called by purchaser upon satisficatory delivery by the supplier to release the payment. Preferred way to complete an agreement.
     */
    function releasePayment() external payable nonReentrant onlyPurchaser isFunded isActive {
        require(amount == this.balance);
        supplier.call{value: amount}("");
        active = false;
        inArbitration = false;
        emit AgreementCompleted();
    }

    /**
     * @dev Called by supplier to return payment if they decide to not deliver the services or goods. Preferred way to cancel an agreement.
     */
    function returnPayment() external nonReentrant onlySupplier isFunded isActive {
        require(amount == this.balance);
        purchaser.call{value: amount}("");
        active = false;
        inArbitration = false;
        emit AgreementCancelled();
        // Maybe have a penalty here?
    }

    /**
     * @dev Called by either supplier or purchaser to request that a third-party arbitrator intervene to settle a dispute.
     */
    function requestArbitration() external onlyEntities isFunded isActive {
        inArbitration = true;
        emit ArbitrationRequested(msg.sender);
    }

    //  -------------------- MULTISIG FUNCTIONS ----------------------
    /**
     * @dev Called by multiSig (signed by both entities) to execute the agreement on-chain.
     */
    function executeAgreement() external onlyMultiSig isNotActive {
        active = true;
        emit AgreementExecuted();
    }

    /**
     * @dev Called by multiSig (signed by both entities) to modify the agreement on-chain.
     */
    function modifyAgreement(uint _amount, bytes _docHash) external payable nonReentrant onlyMultiSig isActive {
        // If funded, return the prior amount to the purchaser and set the funded status to false
        if (funded) {
            purchaser.call{value: amount}("");
            funded = false;
        }

        // Set new amount and docHash
        amount = _amount;
        docHash = _docHash;

        // Emit modified event
        emit AgreementModified();
    }

    //  -------------------- ARBITRATOR FUNCTIONS --------------------
    /**
     * @dev Called by arbitrator to resolve a dispute in favor of the supplier and issue payment.
     */
    function resolveInFavorOfSupplier() external nonReentrant onlyArbitrator isFunded isActive isInArbitration {
        require(amount == this.balance);
        supplier.call{value: amount}("");
        active = false;
        inArbitration = false;
        emit ArbitrationCompleted();
        emit AgreementCompleted();
    }

    /**
     * @dev Called by arbitrator to resolve a dispute in favor of the purchaser and return payment.
     */
    function resolveInFavorOfPurchaser() external nonReentrant onlyArbitrator isFunded isActive isInArbitration {
        require(amount == this.balance);
        purchaser.call{value: amount}("");
        active = false;
        inArbitration = false;
        emit ArbitrationCompleted();
        emit AgreementCompleted();
    }

    /**
     * @dev Called by arbitrator to cancel arbitration without issuing a verdict so the entities can try to work it out once more between themselves.
     */
    function cancelArbitration() external nonReentrant onlyArbitrator isFunded isActive isInArbitration {
        inArbitration = false;
        emit ArbitrationCompleted();
    }

}
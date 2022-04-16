//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@kleros/erc-792/contracts/IArbitrable.sol";
import "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";
import "@kleros/erc-792/contracts/IArbitrator.sol";
import "hardhat/console.sol";

/** @title Weighted Arbitrator
 *   @dev This is a weighted arbitrator that collects rulings from multiple arbitrators and fuses those rulings into one rulling taking into account the weight of each one.
 */
contract WeightedArbitrator is IArbitrator, IArbitrable {
    address public owner = msg.sender;
    uint256 public feePerArbitrator;
    IArbitrator[] public authorizedArbitrators;
    mapping(address => bool) public isAuthorizedArbitrator;

    struct DisputeStruct {
        IArbitrable arbitrated;
        uint256 choices;
        uint256 fee;
        uint256 ruling;
        DisputeStatus status;
        uint256[] subDisputeIDs;
    }

    DisputeStruct[] public disputes;
    mapping(uint256 => DisputeStruct) disputeByID;

    error InsufficientPayment(uint256 _available, uint256 _required);

    constructor(uint256 _feePerArbitrator, IArbitrator[] memory _arbitrators) {
        feePerArbitrator = _feePerArbitrator;
        _addArbitrators(_arbitrators);
    }

    function _addArbitrators(IArbitrator[] memory _arbitrators) private {
        for (uint256 i = 0; i < _arbitrators.length; i++) {
            authorizedArbitrators.push(_arbitrators[i]);
        }
    }

    /** @dev Add an arbitrator to the list of authorized arbitrators. Must be called only by owner.
     *  @param _arbitrator address of the arbitrator contract.
     */
    function addArbitrator(IArbitrator _arbitrator) public onlyOwner {
        authorizedArbitrators.push(_arbitrator);
    }

    /** @dev Return the total number of authorized arbitrators.
     *  @return numberOfArbitrators
     */
    function getNumberOfArbitrators() public view returns (uint256) {
        return authorizedArbitrators.length;
    }

    /** @dev Return arbitrator by its index from the list of authorized arbitrators.
     *  @param _index index of an arbitrator in the list.
     */
    function getArbitrator(uint256 _index) public view returns (IArbitrator) {
        return authorizedArbitrators[_index];
    }

    /** @dev Create a dispute. Must be called by the arbitrable contract.
     *  Must be paid at least arbitrationCost().
     *  a proxy call is invoked on each authorized arbitrator to create sub-dispute and store its ID in Dispute struct.
     *  @param _choices Amount of choices the arbitrator can make in this dispute. When ruling ruling<=choices.
     *  @param _extraData Can be used to give additional info on the dispute to be created.
     *  @return disputeID ID of the dispute created.
     */
    function createDispute(uint256 _choices, bytes memory _extraData)
        public
        payable
        override
        returns (uint256 disputeID)
    {
        uint256 requiredAmount = arbitrationCost(_extraData);
        if (msg.value < requiredAmount) {
            revert InsufficientPayment(msg.value, requiredAmount);
        }
        DisputeStruct memory dispute = DisputeStruct({
            arbitrated: IArbitrable(msg.sender),
            choices: _choices,
            fee: msg.value,
            ruling: 0,
            status: DisputeStatus.Waiting,
            subDisputeIDs: new uint256[](authorizedArbitrators.length)
        });
        for (uint256 i = 0; i < authorizedArbitrators.length; i++) {
            uint256 _subDisputeID = IArbitrator(authorizedArbitrators[i])
                .createDispute{value: feePerArbitrator}(_choices, _extraData);
            dispute.subDisputeIDs[i] = _subDisputeID;
        }
        disputes.push(dispute);
        disputeID = disputes.length - 1;
        disputeByID[disputeID] = dispute;
        emit DisputeCreation(disputeID, IArbitrable(msg.sender));
    }

    /** @dev Return the dispute bu its ID.
     *  Must be paid at least arbitrationCost().
     *  @param _disputeID ID of the dispute.
     *  @return dispute
     */
    function getDisputeByID(uint256 _disputeID)
        public
        view
        returns (DisputeStruct memory)
    {
        return disputeByID[_disputeID];
    }

    function rule(uint256 _disputeID, uint256 _ruling) public override {
        DisputeStruct storage dispute = disputes[_disputeID];
        require(_ruling <= dispute.choices, "Invalid ruling.");
        require(
            dispute.status != DisputeStatus.Solved,
            "The dispute must not be solved already."
        );

        dispute.ruling = _ruling;
        dispute.status = DisputeStatus.Solved;

        payable(msg.sender).transfer(dispute.fee); // Avoid blocking.
        dispute.arbitrated.rule(_disputeID, _ruling);
    }

    /**
     * @dev Compute the overall cost of arbitration based on number of authorized arbitrators. It is recommended not to increase it often, as it can be highly time and gas consuming for the arbitrated contracts to cope with fee augmentation.
     * @param _extraData Can be used to give additional info on the dispute to be created.
     * @return cost Amount to be paid. O(number of arbitrators)
     */
    function arbitrationCost(bytes memory _extraData)
        public
        view
        override
        returns (uint256)
    {
        return feePerArbitrator * authorizedArbitrators.length;
    }

    /** @dev Cost of appeal. Since it is not possible, it's a high value which can never be paid.
     *  @param _disputeID ID of the dispute to be appealed. Not used by this contract.
     *  @param _extraData Not used by this contract.
     *  @return fee Amount to be paid.
     */
    function appealCost(uint256 _disputeID, bytes memory _extraData)
        public
        pure
        override
        returns (uint256)
    {
        return 2**250;
    }

    function appeal(uint256 _disputeID, bytes memory _extraData)
        public
        payable
        override
    {
        uint256 requiredAmount = appealCost(_disputeID, _extraData);
        require(msg.value < requiredAmount, "Insufficient payment");
    }

    function appealPeriod(uint256 _disputeID)
        public
        pure
        override
        returns (uint256 start, uint256 end)
    {
        return (0, 0);
    }

    /** @dev Return the status of a dispute.
     *  @param _disputeID ID of the dispute to rule.
     *  @return status The status of the dispute.
     */
    function disputeStatus(uint256 _disputeID)
        public
        view
        override
        returns (DisputeStatus status)
    {
        status = disputes[_disputeID].status;
    }

    /** @dev Return the ruling of a dispute.
     *  @param _disputeID ID of the dispute to rule.
     *  @return ruling The ruling which would or has been given.
     */
    function currentRuling(uint256 _disputeID)
        public
        view
        override
        returns (uint256 ruling)
    {
        ruling = disputes[_disputeID].ruling;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "can only be called by the owner.");
        _;
    }
}

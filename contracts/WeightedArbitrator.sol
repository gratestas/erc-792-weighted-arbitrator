//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@kleros/erc-792/contracts/IArbitrable.sol";
import "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";
import "@kleros/erc-792/contracts/IArbitrator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/** @title Weighted Arbitrator
 *   @dev This is a weighted arbitrator that collects rulings from multiple arbitrators and fuses those rulings into one rulling taking into account the weight of each one.
 */
contract WeightedArbitrator is IArbitrator, IArbitrable {
    using SafeMath for uint256;

    address public owner = msg.sender;
    uint256 public feePerArbitrator;
    uint256 public collectedRulingCount;
    uint256 public quota = 50;
    IArbitrator[] public authorizedArbitrators;
    mapping(IArbitrator => bool) public isAuthorizedArbitrator;
    mapping(IArbitrator => ArbitratorStruct) public rulingByArbitrator;

    struct ArbitratorStruct {
        uint256 ruling;
        uint256 weight;
    }
    struct DisputeStruct {
        IArbitrable arbitrated;
        uint256 choices;
        uint256 fee;
        uint256 ruling;
        uint256[] subDisputeIDs;
        DisputeStatus status;
    }

    DisputeStruct[] public disputes;

    error InsufficientPayment(uint256 _available, uint256 _required);

    constructor(
        uint256 _feePerArbitrator,
        IArbitrator[] memory _arbitrators,
        uint256[] memory _weights
    ) {
        feePerArbitrator = _feePerArbitrator;
        _addArbitrators(_arbitrators, _weights);
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
        emit DisputeCreation(disputeID, IArbitrable(msg.sender));
    }

    function rule(uint256 _disputeID, uint256 _ruling) public override {
        require(_ruling <= disputes[_disputeID].choices, "Invalid ruling.");
        require(
            disputes[_disputeID].status != DisputeStatus.Solved,
            "The dispute must not be solved already."
        );

        rulingByArbitrator[IArbitrator(msg.sender)].ruling = _ruling;
        collectedRulingCount++;

        if (collectedRulingCount == authorizedArbitrators.length) {
            uint256 weightedRuling = _calculateWeightedRuling();

            disputes[_disputeID].ruling = weightedRuling;
            disputes[_disputeID].status = DisputeStatus.Solved;
            disputes[_disputeID].arbitrated.rule(_disputeID, weightedRuling);
        }
    }

    function _addArbitrators(
        IArbitrator[] memory _arbitrators,
        uint256[] memory _weights
    ) private {
        for (uint256 i = 0; i < _arbitrators.length; i++) {
            authorizedArbitrators.push(_arbitrators[i]);
            isAuthorizedArbitrator[_arbitrators[i]] = true;

            rulingByArbitrator[_arbitrators[i]].ruling = 0;
            rulingByArbitrator[_arbitrators[i]].weight = _weights[i];
        }
    }

    /** @dev Return finale ruling calculated by product summation of product of ruling and weight given by each arbitrator
     * Since option 0 in rulings is reserved for RefusedToArbitrate, finale ruling is likely to be fall in [1,2] range.
     * To comply with the standard range of winnig choices [0,1], summation range is downscaled by substracting 100.
     *  @return weightedRuling a final ruling.
     */
    function _calculateWeightedRuling()
        private
        view
        returns (uint256 weightedRuling)
    {
        uint256 rulingsSum;
        for (uint256 i = 0; i < authorizedArbitrators.length; i++) {
            ArbitratorStruct memory arbitrator = rulingByArbitrator[
                authorizedArbitrators[i]
            ];
            rulingsSum = rulingsSum.add(
                arbitrator.ruling.mul(arbitrator.weight)
            );
        }
        rulingsSum = rulingsSum.sub(100); //shifting value into [0,100] range
        weightedRuling = rulingsSum <= quota ? 1 : 2;
    }

    function arbitrationCost(bytes memory _extraData)
        public
        view
        override
        returns (uint256)
    {
        return feePerArbitrator * authorizedArbitrators.length;
    }

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

    function disputeStatus(uint256 _disputeID)
        public
        view
        override
        returns (DisputeStatus status)
    {
        status = disputes[_disputeID].status;
    }

    function currentRuling(uint256 _disputeID)
        public
        view
        override
        returns (uint256 ruling)
    {
        ruling = disputes[_disputeID].ruling;
    }

    /** @dev Return the total number of authorized arbitrators.
     *  @return numberOfArbitrators
     */
    function getArbitratorCount() public view returns (uint256) {
        return authorizedArbitrators.length;
    }

    /** @dev Return arbitrator by its index from the list of authorized arbitrators.
     *  @param _index index of an arbitrator in the list.
     */
    function getArbitrator(uint256 _index) public view returns (IArbitrator) {
        return authorizedArbitrators[_index];
    }

    /** @dev Set new value of quota. Can be called only by owner.
     *  @param _newQuota new value of quota
     */
    function changeQuota(uint256 _newQuota) public onlyOwner {
        quota = _newQuota;
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
        return disputes[_disputeID];
    }

    function getRulingByArbitrator(IArbitrator _arbitrator)
        public
        view
        returns (uint256)
    {
        return rulingByArbitrator[_arbitrator].ruling;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "can only be called by the owner");
        _;
    }
}

const { expect } = require("chai");
const { ethers } = require("hardhat");

const toWei = (value) => ethers.utils.parseEther(value.toString());
const fromWei = (value) => ethers.utils.formatEther(value.toString());
const toEther = (value) =>
  ethers.utils.parseUnits(
    typeof value === "string" ? value : value.toString(),
    "ether"
  );
describe("WeightedArbitrator", function () {
  let arbitrator, deployer, arbitrable, payer, payee, other;
  let weightedArbitrator,
    centralizedArbitrator_1,
    centralizedArbitrator_2,
    centralizedArbitrator_3,
    centralizedArbitrator_4,
    centralizedArbitrator_5,
    arbitrableEscrow;

  let authorizedArbitrators = [];
  let numberOfArbitrators, totalArbitrationCost;

  const arbitratorExtraData = 0x85;
  const arbitratorFee = 0.1; //ether
  const choices = 2;
  const agreement = "https://kleros.io";
  const paymentToPayee = 0.1;

  beforeEach(async () => {
    [arbitrator, arbitrable, deployer, payer, payee, other] =
      await ethers.getSigners();

    const CentralizedArbitratorFactory = await ethers.getContractFactory(
      "CentralizedArbitrator",
      arbitrator
    );
    centralizedArbitrator_1 = await CentralizedArbitratorFactory.deploy();
    centralizedArbitrator_2 = await CentralizedArbitratorFactory.deploy();
    centralizedArbitrator_3 = await CentralizedArbitratorFactory.deploy();
    centralizedArbitrator_4 = await CentralizedArbitratorFactory.deploy();
    centralizedArbitrator_5 = await CentralizedArbitratorFactory.deploy();

    authorizedArbitrators = [
      centralizedArbitrator_1,
      centralizedArbitrator_2,
      centralizedArbitrator_3,
      centralizedArbitrator_4,
      centralizedArbitrator_5,
    ];
    const WeightedArbitratorFactory = await ethers.getContractFactory(
      "WeightedArbitrator",
      deployer
    );
    weightedArbitrator = await WeightedArbitratorFactory.deploy(
      toEther(arbitratorFee),
      [
        centralizedArbitrator_1.address,
        centralizedArbitrator_2.address,
        centralizedArbitrator_3.address,
        centralizedArbitrator_4.address,
        centralizedArbitrator_5.address,
      ],
      [5, 15, 20, 25, 25]
    );
    numberOfArbitrators = await weightedArbitrator.getArbitratorCount();
    totalArbitrationCost = numberOfArbitrators * arbitratorFee;

    const SimpleEscrowFactory = await ethers.getContractFactory(
      "SimpleEscrow",
      payer
    );
    arbitrableEscrow = await SimpleEscrowFactory.deploy(
      payee.address,
      weightedArbitrator.address,
      agreement,
      { value: toEther(paymentToPayee) }
    );
  });

  describe("on creation", async () => {
    it("Should set the correct total arbitration cost", async () => {
      expect(await weightedArbitrator.arbitrationCost(0x85)).to.equal(
        toEther(arbitratorFee * numberOfArbitrators)
      );
    });
    it("Should set the correct number of arbitrators and validate their addresses", async () => {
      expect(numberOfArbitrators).to.equal(5);

      for (var i = 0; i < numberOfArbitrators; i++) {
        expect(await weightedArbitrator.getArbitrator(i)).to.equal(
          authorizedArbitrators[i].address
        );
      }
    });
    it("allows only owner to change quota", async () => {
      await expect(weightedArbitrator.connect(other).changeQuota(60)).to.be
        .reverted;

      await weightedArbitrator.changeQuota(60);
      expect(await weightedArbitrator.quota()).to.eq(60);
    });
  });
  describe("create dipsute", async () => {
    it("Should create a dispute and check its current state before rulings are given", async () => {
      await weightedArbitrator
        .connect(arbitrable)
        .createDispute(choices, arbitratorExtraData, {
          value: toEther(totalArbitrationCost),
        });

      const dispute = await weightedArbitrator.getDisputeByID(0);
      expect(dispute.arbitrated).to.eq(arbitrable.address);
      expect(dispute.choices).to.eq(2);
      expect(dispute.fee.toString()).to.eq(toWei(totalArbitrationCost));
      expect(dispute.ruling).to.eq(0);
      expect(dispute.status).to.eq(0);
      expect(dispute.subDisputeIDs.length).to.eq(5);
    });
    it("Checks IDs of sub-disputes assuming arbitrators have not created any substantive disputes before ", async () => {
      await weightedArbitrator
        .connect(arbitrable)
        .createDispute(choices, arbitratorExtraData, {
          value: toEther(totalArbitrationCost),
        });

      const dispute = await weightedArbitrator.getDisputeByID(0);
      for (var i = 0; i < numberOfArbitrators; i++) {
        expect(dispute.subDisputeIDs[i]).to.eq(0);
      }
    });
    it("Checks IDs of sub-disputes assuming some arbitrators could have created substantive disputes", async () => {
      // this dispute is created to differentiate dispute's indexes in arbitrator and weighted arbitrator contracts
      await authorizedArbitrators[2]
        .connect(other)
        .createDispute(choices, arbitratorExtraData, {
          value: toEther(arbitratorFee),
        });
      await weightedArbitrator
        .connect(arbitrable)
        .createDispute(choices, arbitratorExtraData, {
          value: toEther(totalArbitrationCost),
        });

      const dispute = await weightedArbitrator.getDisputeByID(0);
      expect(dispute.subDisputeIDs[0]).to.eq(0);
      expect(dispute.subDisputeIDs[1]).to.eq(0);
      expect(dispute.subDisputeIDs[2]).to.eq(1);
    });

    it("Checks if weighted arbitrator is an arbitrable contract in any sub-dispute", async () => {
      // authorized arbitrator creates a substantive dispute
      await authorizedArbitrators[0]
        .connect(other)
        .createDispute(choices, arbitratorExtraData, {
          value: toEther(arbitratorFee),
        });
      let arbitrated = (await authorizedArbitrators[0].disputes(0)).arbitrated;
      expect(arbitrated).to.eq(other.address);

      await weightedArbitrator
        .connect(arbitrable)
        .createDispute(choices, arbitratorExtraData, {
          value: toEther(totalArbitrationCost),
        });

      // check if weightedArbitrator is the aribtrator in the second dispute created by authorizedArbitrator[0]
      const parentDispute = await weightedArbitrator.getDisputeByID(0);
      const subDisputeID = parentDispute.subDisputeIDs[0];
      arbitrated = (await authorizedArbitrators[0].disputes(subDisputeID))
        .arbitrated;
      expect(arbitrated).to.eq(weightedArbitrator.address);
    });
  });

  describe("rule dispute", async () => {
    it("authorized arbitrators rule dispute raised by 'payer' party of simple escrow ", async () => {
      // payer reclaims funds by depositing arbitration fee
      await arbitrableEscrow.reclaimFunds({
        value: toEther(totalArbitrationCost),
      });

      const payerBalanceBefore = await ethers.provider.getBalance(
        payer.address
      );

      //  payee deposits arbitration fee in time. Dispute gets created
      await arbitrableEscrow.connect(payee).depositArbitrationFeeForPayee({
        value: toEther(totalArbitrationCost),
      });

      //authorized arbitrators rule disptue.
      await authorizedArbitrators[0].rule(0, 1);
      await authorizedArbitrators[1].rule(0, 2);
      await authorizedArbitrators[2].rule(0, 2);
      await authorizedArbitrators[3].rule(0, 1);
      await authorizedArbitrators[4].rule(0, 2);

      // check ruling given by first authorized arbitrator
      const rulingOfArbitrator_1 =
        await weightedArbitrator.getRulingByArbitrator(
          authorizedArbitrators[0].address
        );
      expect(rulingOfArbitrator_1).to.eq(1);

      // check dispute's status and final ruling
      const dispute = await weightedArbitrator.getDisputeByID(0);
      expect(dispute.arbitrated).to.eq(arbitrableEscrow.address);
      expect(dispute.ruling).to.eq(1); // payer wins
      expect(dispute.status).to.eq(2); // status = solved

      // payer wins dispute and gets arbitration + deposit amount rufunded
      const expectedBalanceDelta = totalArbitrationCost + paymentToPayee;
      const tolerance = 0.00001; // due to gas consumption

      const payerBalanceAfter = await ethers.provider.getBalance(payer.address);
      const balanceDelta = payerBalanceAfter - payerBalanceBefore;

      expect(fromWei(balanceDelta) - expectedBalanceDelta).to.be.most(
        tolerance
      );
    });
  });
});

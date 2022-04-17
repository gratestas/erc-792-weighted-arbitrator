### ERC-792: Simple (Non-appeable) Weighted Arbitrator
The smart contract collects rulings from multiple arbitrators and fuses those into a single ruling based on the weight of each arbitrator. 

Weighted Arbitrator implements `IArbitrator` and `IArbitrable` interfaces derived from ERC-792 Standard. This means that `WeightedArbitrator` is an `arbitrator` for any arbitrable contract,  while it is `arbitrable` for each arbitrator it pulls ruling from. The total arbitration cost is correlated with the number of arbitrators drawn into the dispute in the form of `O(numberOfArbitrators)`

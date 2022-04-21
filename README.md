## ERC-792: Simple (Non-appeable) Weighted Arbitrator
The smart contract collects rulings from multiple arbitrators and fuses those into a single ruling based on the weight of each arbitrator. 

Weighted Arbitrator implements `IArbitrator` and `IArbitrable` interfaces derived from ERC-792 Standard. This means that `WeightedArbitrator` is an `arbitrator` for any arbitrable contract,  while it is `arbitrable` for each arbitrator it receives ruling from. The total arbitration cost is correlated with the number of arbitrators drawn into the dispute in the form of `O(numberOfArbitrators)`
</br>
</br>
</br>     
## Weighted Ruling Mechanism
A simple weighted average equation is used to fuse all rulings collected from a set of authorized arbitrators into one final weighted ruling, taking into account the ruling power of each. 
</br>
</br>
<div align="center"><img src="https://latex.codecogs.com/gif.latex?%5Clarge%5Cmathit%7BweightedRuling%7D%3D%5CLarge%5Cfrac%7B%5Csum_%7Bi%3D0%7D%5E%7BN%7D%7Br_iw_i%7D%7D%7B%5Csum_%7Bi%3D0%7D%5E%7BN%7D%7Bw_i%7D%20%7D"></div>
</br>
<div align="center"><img src="https://latex.codecogs.com/gif.latex?where%5C%3A%20%5C%3A%20%5Csum_%7Bi%3D0%7D%5E%7BN%7D%7Bw_i%7D%3D100"></div>

where:</br>
<img src="https://render.githubusercontent.com/render/math?math=\Large\r_i">- ruling of `i-th` arbitrator </br>
<img src="https://render.githubusercontent.com/render/math?math=\Large\w_i">- weighting factor allocated for `i-th` arbitrator


#### Final decision
For the sake of simplicity, the `numberOfChoices` is kept to be limited by 2. A `quota` (the threshold required to pass for the majority) state variable is introduced to determine the final decision.
</br>
</br>
</br>
<div align="center"><img src="https://latex.codecogs.com/gif.latex?%5Clarge%5Ctextit%7BfinalRuling%7D%3D%5Clarge%5Cleft%5C%7B%5Cbegin%7Bmatrix%7D%202%20%26%5Ctext%7Bif%20%24wieghtedRuling%3Equota%24%7D%20%5C%5C%201%20%26%20%5Ctext%7Botherwise.%7D%20%5Cend%7Bmatrix%7D%5Cright."></div>
</br>
<div align="center"><img src="https://latex.codecogs.com/gif.latex?where%5C%3A%20%5C%3A%20quota%5Cin%20%2850%2C100%29"></div>


## Testing
```
// Clone the repository
git clone https://github.com/gratestas/erc-792-weighted-arbitrator.git

// Navigate into repository
cd erc-792-weighted-arbitrator

// Install the dependencies
yarn install

// Run test
npx hardhat test
```

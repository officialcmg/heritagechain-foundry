
# 💎 HeritageChain — Smart Contract-Based Digital Legacy Manager

HeritageChain is a decentralized smart contract system designed to handle the secure distribution of digital assets (ETH, ERC20, ERC721) to beneficiaries after the original owner can no longer manage them. Whether triggered by time or manually, the system ensures your assets are distributed transparently and according to your wishes.

---

## 🧠 Overview

HeritageChain helps Ethereum users automate the inheritance and distribution of their digital assets via:

- ✅ **Time-based triggers** for automated distribution.
- ✅ **Voluntary activation** for manual release.
- ✅ Support for **ETH, ERC20 tokens, and ERC721 NFTs**.
- ✅ Beneficiaries & distribution percentages can be fully customized.
- ✅ One active plan per user at a time.

---

## 🏗️ Architecture

### 1️⃣ `HeritageChainFactory.sol`
The **factory contract** is responsible for deploying one personal `HeritageChain` contract per user, enforcing only one active legacy plan at a time.

Main features:

- Deploy a new `HeritageChain` for your address.
- Retrieve your deployed contract.
- Ensures that only one contract per user can hold active, undistributed assets.

---

### 2️⃣ `HeritageChain.sol`
The **HeritageChain contract** represents an individual user’s digital legacy plan.

Main features:

- Deposit assets: `ETH`, `ERC20`, `ERC721`.
- Assign multiple beneficiaries with share-based splits.
- Define a **trigger**: 
   - ⏰ `TIME_BASED` — automates distribution after a specified date.
   - 🙋‍♂️ `VOLUNTARY` — allows the owner to release assets manually.
- Automatic and transparent distribution once the trigger is activated.
- Cancel plan anytime if conditions allow.

---

## 💡 Usage Flow

1. **Deploy a HeritageChain contract**  
Via `HeritageChainFactory.deployHeritageChain()`.

2. **Deposit assets**  
Using functions:  
- `depositETH()`
- `depositERC20()`
- `depositERC721()`

3. **Assign beneficiaries**  
Call `configureBeneficiaries()` with addresses and share percentages (must sum to 100%).

4. **Set trigger type**  
- `setTimeTrigger()` (time-based distribution) or  
- `setVoluntaryTrigger()` (owner must later manually confirm).

5. **Trigger activation**  
- Automatically, if `TIME_BASED` and time has passed.
- Manually by calling `activateVoluntaryTrigger()`.

6. ✅ **Automatic distribution** is executed by the contract to all beneficiaries.

---

## 🔐 Security Features

- Uses OpenZeppelin libraries for token interactions, ownership control, and reentrancy protection.
- Trigger system prevents premature asset distribution.
- Single contract per user prevents confusion or double claims.

---

## ⚠️ Disclaimer

HeritageChain is a self-hosted, trustless smart contract. Improper configuration (wrong beneficiary addresses, incorrect percentages, or early triggers) may lead to permanent asset loss. Use with care and thoroughly test on testnets before deploying on mainnet.

---

## 🧑‍💻 Author

**officialcmg**  
Ethereum developer & smart contract enthusiast.

---




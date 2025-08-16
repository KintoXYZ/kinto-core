// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {SuperToken} from "@kinto-core/tokens/bridged/SuperToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FixKintoPreHack is MigrationHelper {
    using Strings for string;

    struct Record {
        address user;
        uint256 shares;
    }

    /**
     * @dev Reads a simple 2-column CSV (address,value) and appends to `records`.
     *      Accepts either comma or TAB as separator and ignores blank lines
     *      & lines starting with '#'.
     */
    function _readCsvIntoRecords(string memory path) internal {
        string memory raw = vm.readFile(path);        // forge-std cheat-code
        bytes  memory data = bytes(raw);

        uint256 i;                                    // cursor in `data`
        while (i < data.length) {
            // ── 1. Skip blank lines / comments ───────────────────────────
            if (_isEOL(data[i])) { i++; continue; }
            if (data[i] == "#") {                     // comment line
                while (i < data.length && !_isEOL(data[i])) i++;
                continue;
            }

            // ── 2. Parse address token ───────────────────────────────────
            uint256 start = i;
            while (i < data.length && !_isSep(data[i])) i++;
            string memory addrStr = _slice(data, start, i - start);
            address user = vm.parseAddress(addrStr);

            // consume separator (, or \t)
            if (i < data.length) i++;

            // ── 3. Parse value token ─────────────────────────────────────
            start = i;
            while (i < data.length && !_isEOL(data[i])) i++;
            string memory valStr = _slice(data, start, i - start);
            uint256 shares = vm.parseUint(valStr);

            // push record
            records.push(Record({user: user, shares: shares}));

            // consume newline
            while (i < data.length && _isEOL(data[i])) i++;
        }
    }

    /* ──────────────── tiny string/byte helpers (pure) ───────────── */

    function _slice(
        bytes memory src,
        uint256      start,
        uint256      len
    ) internal pure returns (string memory) {
        bytes memory out = new bytes(len);
        for (uint256 j; j < len; ++j) out[j] = src[start + j];
        return string(out);
    }

    function _isSep(bytes1 b)  internal pure returns (bool) {
        return b == "," || b == "\t";
    }

    function _isEOL(bytes1 b)  internal pure returns (bool) {
        return b == "\n" || b == "\r";
    }


    Record[] public records;
    string internal constant CSV_PATH =   "script/data/mint_records.csv";

    function run() public override {
        super.run();

        console2.log("Executing with address", msg.sender);

        if (block.chainid != ARBITRUM_CHAINID) {
            console2.log("This script is meant to be run on the chain: %s", ARBITRUM_CHAINID);
            return;
        }

        SuperToken kintoToken = SuperToken(_getChainDeployment("K"));

        _readCsvIntoRecords(CSV_PATH);

        uint256 batchIndexStartingEnd = 6; // 6 done
        uint256 batchSize = batchIndexStartingEnd == 6 ? 662 : 700;

        uint256 start = batchIndexStartingEnd == 6 ? 0 : records.length > (batchSize * batchIndexStartingEnd) ? records.length - (batchSize * batchIndexStartingEnd) : 0;
        address[] memory users = new address[](batchSize);
        uint256[] memory shares = new uint256[](batchSize);
        uint256 total = 0;
        for (uint256 i = start; i < start + batchSize; i++) {
            users[i - start] = records[i].user;
            shares[i - start] = records[i].shares;
            total += records[i].shares;
        }

        vm.broadcast(deployerPrivateKey);
        kintoToken.batchMint(users, shares);

        require(kintoToken.balanceOf(records[start].user) == records[start].shares, "Did not mint");
        require(kintoToken.balanceOf(records[start + 1].user) == records[start + 1].shares, "Did not mint");
        require(
            kintoToken.balanceOf(records[start + batchSize - 1].user)
                == records[start + batchSize - 1].shares,
            "Did not mint"
        );
        console2.log("total", total);

        uint256 totalSupply = kintoToken.totalSupply();
        require(totalSupply <= 1_600_000e18, "Total Supply under control");

        if (batchIndexStartingEnd == 5) {
            require(total >= 2807e18 && total <= 2808e18, "Total minted in this batch is not accurate");
        }

        if (batchIndexStartingEnd == 6) {
            // Removes overhang from the safe
            uint256 vaultBalance = 1553025704644939812527643;
            console2.log("difference", totalSupply - vaultBalance);
            if (totalSupply > vaultBalance) {
                vm.broadcast(deployerPrivateKey);
                kintoToken.burn(0x8bFe32Ac9C21609F45eE6AE44d4E326973700614, totalSupply - vaultBalance);
                console2.log("burned", totalSupply - vaultBalance);
            }
            // Remove minter role
            vm.broadcast(deployerPrivateKey);
            kintoToken.renounceRole(0x7b765e0e932d348852a6f810bfa1ab891e259123f02db8cdcde614c570223357, 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c);
            require(kintoToken.hasRole(0x7b765e0e932d348852a6f810bfa1ab891e259123f02db8cdcde614c570223357, 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c) == false, "Minter role removed");
            require(kintoToken.totalSupply() == vaultBalance, "Total Supply exact");
        }

    }
}

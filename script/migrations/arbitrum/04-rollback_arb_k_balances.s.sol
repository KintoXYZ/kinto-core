// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2, Script} from "forge-std/console2.sol";
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
    string internal constant CSV_PATH =   "data/mint_records.csv";

    function run() public override {
        super.run();

        console.log("Executing with address", msg.sender);

        if (block.chainid != ARBITRUM_CHAINID) {
            console2.log("This script is meant to be run on the chain: %s", ARBITRUM_CHAINID);
            return;
        }

        SuperToken kintoToken = BridgedKinto(_getChainDeployment("K"));

        _readCsvIntoRecords(CSV_PATH);

        uint256 batchSize = 700;

        uint256 totalMintRecords = records.length;
        uint256 start = 0;
        address[] memory users = new address[](batchSize);
        uint256[] memory shares = new uint256[](batchSize);
        uint256[] memory balances = new uint256[](batchSize);
        uint256 total = 0;
        for (uint256 i = start; i < start + batchSize; i++) {
            users[i - start] = records[i].user;
            shares[i - start] = records[i].shares;
            balances[i - start] = kintoToken.balanceOf(records[i].user);
            total += records[i].shares;
        }

        _handleOps(
            abi.encodeWithSelector(BridgedToken.batchMint.selector, users1, shares1),
            payable(_getChainDeployment("K"))
        );

        require(kintoToken.balanceOf(records[start].user) == balances[0] + records[start].shares, "Did not mint");
        require(kintoToken.balanceOf(records[start + 1].user) == balances[1] + records[start + 1].shares, "Did not mint");
        require(
            kintoToken.balanceOf(records[start + batchSize - 1].user)
                == balances[batchSize - 1] + records[start + batchSize - 1].shares,
            "Did not mint"
        );
        require(total >= 1802e18 && total <= 1803e18, "Total minted");
        console2.log("total", total);

        require(kintoToken.totalSupply() <= 1_600_000e18, "Total Supply under control");
    }
}

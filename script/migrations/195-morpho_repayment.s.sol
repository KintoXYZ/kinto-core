// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MorphoRepayment} from "@kinto-core/vaults/MorphoRepayment.sol";

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {
    IERC20Upgradeable,
    IERC20MetadataUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "@kinto-core-test/helpers/ArrayHelpers.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    using ArrayHelpers for *;

    struct Record {
        address user;
        uint256 collateralLocked;
        uint256 usdcLent;
        uint256 usdcBorrowed;
    }

    Record[] public records;
    MorphoRepayment.UserInfo[] public infos;

    address public constant SOCKET_APP = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
    address public constant K = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address public constant USDC = 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E;
    //May 15th, 2025, 10:00:00 AM PT.
    uint256 public constant END_TIME = 1747238400;

    function run() public override {
        super.run();

        if (_getChainDeployment("MorphoRepayment") != address(0)) {
            console2.log("MorphoRepayment is deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        MorphoRepayment impl = new MorphoRepayment(IERC20Upgradeable(K), IERC20Upgradeable(USDC));

        (bytes32 salt, address expectedAddress) =
            mineSalt(keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(impl), ""))), "5A1E00");

        vm.broadcast(deployerPrivateKey);
        UUPSProxy proxy = new UUPSProxy{salt: salt}(address(impl), "");
        MorphoRepayment morphoRepayment = MorphoRepayment(address(proxy));

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.addAppContracts.selector, SOCKET_APP, [address(morphoRepayment)].toMemoryArray()
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(MorphoRepayment.initialize.selector),
            payable(kintoAdminWallet),
            address(proxy),
            0,
            address(0),
            privateKeys
        );

        // Push records
        records.push(
            Record({
                user: 0x0000000000000000000000000000000000000000,
                collateralLocked: 1000000000000000000000000,
                usdcLent: 1000000000000000000000000,
                usdcBorrowed: 10000000
            })
        );

        // Set User Info
        uint256 totalMintRecords = records.length;
        address[] memory users1 = new address[](totalMintRecords);
        uint256 totalCollateralLocked = 0;
        uint256 totalUsdcLent = 0;
        uint256 totalUsdcBorrowed = 0;
        for (uint256 i = 0; i < records.length; i++) {
            users1[i] = records[i].user;
            totalCollateralLocked += records[i].collateralLocked;
            totalUsdcLent += records[i].usdcLent;
            totalUsdcBorrowed += records[i].usdcBorrowed;
            infos.push(
                MorphoRepayment.UserInfo({
                    collateralLocked: records[i].collateralLocked,
                    usdcLent: records[i].usdcLent,
                    usdcBorrowed: records[i].usdcBorrowed,
                    usdcRepaid: 0,
                    isRepaid: false
                })
            );
        }

        _handleOps(
            abi.encodeWithSelector(MorphoRepayment.setUserInfo.selector, users1, infos), address(morphoRepayment)
        );

        assertEq(morphoRepayment.TOTAL_COLLATERAL(), totalCollateralLocked);
        assertEq(morphoRepayment.TOTAL_DEBT(), totalUsdcLent);
        assertEq(morphoRepayment.TOTAL_USDC_LENT(), totalUsdcBorrowed);

        assertEq(address(morphoRepayment), address(expectedAddress));
        assertEq(address(morphoRepayment.collateralToken()), address(K));
        assertEq(address(morphoRepayment.debtToken()), address(USDC));
        assertEq(morphoRepayment.totalCollateralUnlocked(), 0);
        assertEq(morphoRepayment.totalDebtRepaid(), 0);
        saveContractAddress("MorphoRepayment", address(morphoRepayment));
        saveContractAddress("MorphoRepayment-impl", address(impl));
    }
}

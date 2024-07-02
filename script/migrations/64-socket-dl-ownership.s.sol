// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "../../src/tokens/bridged/BridgedToken.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";

interface AccessControl {
    function owner() external view returns (address);
    function nominateOwner(address nominee_) external;
    function grantRole(bytes32 role_, address grantee_) external;
    function revokeRole(bytes32 role_, address revokee_) external;
    function hasRole(bytes32 role_, address address_) external view returns (bool);
    function claimOwner() external;
}

contract KintoMigration64DeployScript is MigrationHelper {
    using LibString for *;
    using stdJson for string;

    address SAFE_ADDRESS = 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82;
    address KINTO_DEPLOYER;

    address[30] allContracts = [
        0x56Ac0e336f0c3620dCaF8d361E8E14eA73C31f5d, // SignatureVerifier
        0x9652Dd5e1388CA80712470122F27be0d1c33B48b, // Hasher
        0x35B1Ca86D564e69FA38Ee456C12c78A62e78Aa4c, // CapacitorFactory
        0x3e9727470C66B1e77034590926CDe0242B5A3dCc, // Socket (GOVERNANCE_ROLE)
        0x6c914cc610e9a05eaFFfD79c10c60Ad1704717E5, // ExecutionManager (GOVERNANCE_ROLE, WITHDRAW_ROLE, FEES_UPDATER_ROLE)
        0x6332e56A423480A211E301Cb85be12814e9238Bb, // TransmitManager (GOVERNANCE_ROLE, WITHDRAW_ROLE, FEES_UPDATER_ROLE)
        0x516302D1b25e5F6d1ac90eF7256270cd799524CF, // FastSwitchboard (GOVERNANCE_ROLE, TRIP_ROLE, UN_TRIP_ROLE, WITHDRAW_ROLE, FEES_UPDATER_ROLE)
        0x2B98775aBE9cDEb041e3c2E56C76ce2560AF57FB, // OptimisticSwitchboard (GOVERNANCE_ROLE, TRIP_ROLE, UN_TRIP_ROLE, FEES_UPDATER_ROLE)
        0x12FF8947a2524303C13ca7dA9bE4914381f6557a, // SocketBatcher
        0x03B73a2c5c5D22D125E9572983Cc9Db33f9B5E9d, // Counter (does not have roles)
        0x72846179EF1467B2b71F2bb7525fcD4450E46B2A, // SocketSimulator
        0x897DA4D039f64090bfdb33cd2Ed2Da81adD6FB02, // SimulatorUtils
        0xa7527C270f30cF3dAFa6e82603b4978e1A849359, // SwitchboardSimulator
        0x6dbB5ee7c63775013FaF810527DBeDe2810d7Aee, // CapacitorSimulator
        // switchboard contracts
        // ethereum
        0xC2a01Cd64DCEbd3f5531B9847bE9ac6EE3c1f69A,
        0x20cD1b923C16551e8db1eFD462B8ed3d7d7f92F6,
        0x5EA0bC9Dd767439D7000d829D3a46E38ef94E63d,
        0xC3230427dAA959E4b12FC87a1bc47add3d565529,
        // optimism
        0x56D77fA62C98ccf4c45E645bcFD83626a16B7C35,
        0x1595aece46e3aB756949BF314aEAfAfA47D3C4a9,
        0x806dd530F020F27d9bb3be4DDC669E7191c70705,
        0x943cB1e125eC092F26d9e0741469488C5D70FB43,
        // base
        0xea094af8cB914BdD0662a47f5e141e08E5A27A82,
        0x70994d59C52A5aA492432a1703b8fe639D1cf53C,
        0x8521206093E554fd11ebAdC1748d60A33B41DE66,
        0x673c50C88ef5183459682b53b47864C0fd01b52B,
        0x2321C637686b8dA2e01c60D72fD82a595879da00,
        // arbitrum
        0xfD894892Ed2723Caa147C76283e0ea72596c1fA5,
        0x45f791cA90E23D431F08f2Ec6B2202028D2489ef,
        0x7d38196535734a921Aa5C25c9AFB0E31F873f6f0
    ];

    address[5] contractsWithGovernance = [
        0x3e9727470C66B1e77034590926CDe0242B5A3dCc, // Socket
        0x6c914cc610e9a05eaFFfD79c10c60Ad1704717E5, // ExecutionManager
        0x6332e56A423480A211E301Cb85be12814e9238Bb, // TransmitManager
        0x516302D1b25e5F6d1ac90eF7256270cd799524CF, // FastSwitchboard
        0x2B98775aBE9cDEb041e3c2E56C76ce2560AF57FB // OptimisticSwitchboard
    ];

    address[4] contractsWithWithdraw = [
        0x6c914cc610e9a05eaFFfD79c10c60Ad1704717E5, // ExecutionManager
        0x6332e56A423480A211E301Cb85be12814e9238Bb, // TransmitManager
        0x516302D1b25e5F6d1ac90eF7256270cd799524CF, // FastSwitchboard
        0x2B98775aBE9cDEb041e3c2E56C76ce2560AF57FB // OptimisticSwitchboard
    ];

    address[4] contractsWithFeesUpdater = [
        0x6c914cc610e9a05eaFFfD79c10c60Ad1704717E5, // ExecutionManager
        0x6332e56A423480A211E301Cb85be12814e9238Bb, // TransmitManager
        0x516302D1b25e5F6d1ac90eF7256270cd799524CF, // FastSwitchboard
        0x2B98775aBE9cDEb041e3c2E56C76ce2560AF57FB // OptimisticSwitchboard
    ];

    // both TRIP_ROLE and UN_TRIP_ROLE roles
    address[2] contractsWithTrip = [
        0x516302D1b25e5F6d1ac90eF7256270cd799524CF, // FastSwitchboard
        0x2B98775aBE9cDEb041e3c2E56C76ce2560AF57FB // OptimisticSwitchboard
    ];

    function run() public override {
        super.run();
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        KINTO_DEPLOYER = vm.addr(deployerPrivateKey);

        whitelistAllContracts();

        bytes32 role = keccak256("RESCUE_ROLE");
        handleRole(role);

        role = keccak256("GOVERNANCE_ROLE");
        handleRole(role);

        role = keccak256("WITHDRAW_ROLE");
        handleRole(role);

        role = keccak256("FEES_UPDATER_ROLE");
        handleRole(role);

        role = keccak256("TRIP_ROLE");
        handleRole(role);

        role = keccak256("UN_TRIP_ROLE");
        handleRole(role);

        // nominate new owner
        console2.log("\nNominating new owners...");
        bytes[] memory selectorsAndParams = new bytes[](allContracts.length);
        address[] memory tos = new address[](allContracts.length);

        bytes memory selectorAndParams = abi.encodeWithSelector(AccessControl.nominateOwner.selector, SAFE_ADDRESS);
        for (uint256 i = 0; i < allContracts.length; i++) {
            console2.log("- Nominating", SAFE_ADDRESS, "as owner of", allContracts[i]);
            selectorsAndParams[i] = selectorAndParams;
            tos[i] = allContracts[i];
        }
        _handleOpsBatch(selectorsAndParams, tos, deployerPrivateKey);

        // validate Safe can claim ownership
        vm.startPrank(SAFE_ADDRESS);
        for (uint256 i = 0; i < allContracts.length; i++) {
            AccessControl(allContracts[i]).claimOwner();
            require(AccessControl(allContracts[i]).owner() == SAFE_ADDRESS, "Ownership not transferred");
        }
        vm.stopPrank();
    }

    function whitelistAllContracts() internal {
        console2.log("Whitelisting all contracts...");
        address[] memory apps = new address[](allContracts.length);
        for (uint256 i = 0; i < allContracts.length; i++) {
            apps[i] = allContracts[i];
        }

        bool[] memory flags = new bool[](allContracts.length);
        for (uint256 i = 0; i < allContracts.length; i++) {
            flags[i] = true;
        }

        bytes memory selectorAndParam = abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags);
        _handleOps(selectorAndParam, _getChainDeployment("KintoWallet-admin"), deployerPrivateKey);
    }

    function handleRole(bytes32 role) internal {
        address[] memory contracts = getContracts(role);

        console2.log("Revoking roles...");
        bytes[] memory selectorAndParams;
        address[] memory tos;

        bytes memory selectorAndParam = abi.encodeWithSelector(AccessControl.revokeRole.selector, role, KINTO_DEPLOYER);
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] == 0x03B73a2c5c5D22D125E9572983Cc9Db33f9B5E9d) {
                console2.log("- Skipping Counter contract");
                continue;
            }
            bool hasRole = AccessControl(contracts[i]).hasRole(role, KINTO_DEPLOYER);
            if (hasRole) {
                console2.log("- Revoking role from %s on %s", KINTO_DEPLOYER, contracts[i]);
                selectorAndParams[i] = selectorAndParam;
                tos[i] = contracts[i];
            } else {
                console2.log("- Role already revoked from %s on %s", KINTO_DEPLOYER, contracts[i]);
            }
        }
        _handleOpsBatch(selectorAndParams, tos, deployerPrivateKey);

        console2.log("Granting roles...");
        selectorAndParams = new bytes[](contracts.length);
        tos = new address[](contracts.length);

        selectorAndParam = abi.encodeWithSelector(AccessControl.grantRole.selector, role, SAFE_ADDRESS);
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] == 0x03B73a2c5c5D22D125E9572983Cc9Db33f9B5E9d) {
                console2.log("- Skipping Counter contract");
                continue;
            }
            bool hasRole = AccessControl(contracts[i]).hasRole(role, SAFE_ADDRESS);
            if (hasRole) {
                console2.log("- Role already granted to %s on %s", SAFE_ADDRESS, contracts[i]);
            } else {
                console2.log("- Granting role to %s on %s", SAFE_ADDRESS, contracts[i]);
                selectorAndParams[i] = selectorAndParam;
                tos[i] = contracts[i];
            }
        }
        _handleOpsBatch(selectorAndParams, tos, deployerPrivateKey);

        // check roles
        console2.log("\nValidating roles...");
        for (uint256 i = 0; i < contracts.length; i++) {
            AccessControl contractInstance = AccessControl(contracts[i]);
            if (contracts[i] == 0x03B73a2c5c5D22D125E9572983Cc9Db33f9B5E9d) continue;
            require(!contractInstance.hasRole(role, KINTO_DEPLOYER), "Role not revoked");
            require(contractInstance.hasRole(role, SAFE_ADDRESS), "Role not set");
        }
    }

    function getContracts(bytes32 role) public view returns (address[] memory contracts) {
        if (role == keccak256("RESCUE_ROLE")) {
            contracts = new address[](allContracts.length);
            for (uint256 i = 0; i < allContracts.length; i++) {
                contracts[i] = allContracts[i];
            }
        } else if (role == keccak256("GOVERNANCE_ROLE")) {
            contracts = new address[](contractsWithGovernance.length);
            for (uint256 i = 0; i < contractsWithGovernance.length; i++) {
                contracts[i] = contractsWithGovernance[i];
            }
        } else if (role == keccak256("WITHDRAW_ROLE")) {
            contracts = new address[](contractsWithWithdraw.length);
            for (uint256 i = 0; i < contractsWithWithdraw.length; i++) {
                contracts[i] = contractsWithWithdraw[i];
            }
        } else if (role == keccak256("FEES_UPDATER_ROLE")) {
            contracts = new address[](contractsWithFeesUpdater.length);
            for (uint256 i = 0; i < contractsWithFeesUpdater.length; i++) {
                contracts[i] = contractsWithFeesUpdater[i];
            }
        } else if (role == keccak256("TRIP_ROLE")) {
            contracts = new address[](contractsWithTrip.length);
            for (uint256 i = 0; i < contractsWithTrip.length; i++) {
                contracts[i] = contractsWithTrip[i];
            }
        } else if (role == keccak256("UN_TRIP_ROLE")) {
            contracts = new address[](contractsWithTrip.length);
            for (uint256 i = 0; i < contractsWithTrip.length; i++) {
                contracts[i] = contractsWithTrip[i];
            }
        }
    }
}

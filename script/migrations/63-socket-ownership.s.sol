// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "../../src/tokens/bridged/BridgedToken.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

interface AccessControl {
    function owner() external view returns (address);
    function nominateOwner(address nominee_) external;
    function grantRole(bytes32 role_, address grantee_) external;
    function revokeRole(bytes32 role_, address revokee_) external;
    function hasRole(bytes32 role_, address address_) external view returns (bool);
    function claimOwner() external;
}

contract KintoMigration63DeployScript is MigrationHelper {
    using LibString for *;
    using stdJson for string;

    address kintoMainnetSafeAddress = 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82;
    address kintoBaseSafeAddress = 0x45e9deAbb4FdD048Ae38Fce9D9E8d68EC6f592a2;
    address kintoArbitrumSafeAddress = 0x8bFe32Ac9C21609F45eE6AE44d4E326973700614;

    address[39] mainnetContracts = [
        0x12Cf431BdF7F143338cC09A0629EDcCEDCBCEcB5,
        0x1991Fb3e5EC42A5eee9acC70fB30b0DBEF34B667,
        0xAc00056920EfF02831CAf0baF116ADf6B42D9ad1,
        0xc5d01939Af7Ce9Ffc505F0bb36eFeDde7920f2dc,
        0x05369D989D9dD9cD6537E667865Ee8157d5EE91B,
        0x83C6d6597891Ad48cF5e0BA901De55120C37C6bE,
        0x00A0c9d82B95a17Cdf2D46703F2DcA13EB0E8A94,
        0x47469683AEAD0B5EF2c599ff34d55C3D998393Bf,
        0xe987a57DA7Ab112B1bDc7AA704E6EA943760d252,
        0x755cD5d147036E11c76F1EeffDd94794fC265f0d,
        0xD97E3cD27fb8af306b2CD42A61B7cbaAF044D08D,
        0x935f1C29Db1155c3E0f39F644DF78DDDBD4757Ff,
        0x351d8894fB8bfa1b0eFF77bFD9Aab18eA2da8fDd,
        0x70ae312d3f1c9116BF89db833DaDc060D4AD820F,
        0x266abd77Da7F877cdf93c0dd5782cC61Fa29ac96,
        0xdf34E61B6e7B9e348713d528fEB019d504d38c1e,
        0x9d46297E4d0fb4D911bDE9746dBb7077d897a908,
        0x73E0d4953c356a5Ca3A3D172739128776B2920b5,
        0xdb161cdc9c11892922F7121a409b196f3b00e640,
        0x7277c48c2b8a303feDa28b45C693651c3dC44160,
        0x642c4c33301EF5837ADa6E74F15Aa939f3951Fff,
        0xc7a542f73049C11f9719Be6Ff701fCA882D60020,
        0xCFfEa712C4B63d2498747943eB3467D12db6b476,
        0x170fFDe318B514B029E1B1eC4F096C7e1bDeaeA8,
        0x5B8Ae1C9c5970e2637Cf3Af431acAAebEf7aFb85,
        0x6d2b0A4588a7F7d88298B0089cA396506A1D42d8,
        0xF5992B6A0dEa32dCF6BE7bfAf762A4D94f139Ea7,
        0x43b718Aa5e678b08615CA984cbe25f690B085b32,
        0x872407261Fd595363c108cE7f0e0272f24626189,
        0xE274dB6b891159547FbDC18b07412EE7F4B8d767,
        0xD357F7Ec4826Bd1234CDA2277B623F6dE7dA56Dc,
        0xb787D2187be7198751E0EB2dDd5279710Cf39744,
        0xC331BEeC6e36c8Df4FDD7e432de95863E7f80d67,
        0xeB66259d2eBC3ed1d3a98148f6298927d8A36397,
        0xBCbf273F2a16137b7AD376c8c5ea81F69F7b0F6C,
        0xE2c2291B80BFC8Bd0e4fc8Af196Ae5fc9136aeE0,
        0x95d60E34aB2E626407d98dF8C240e6174e5D37E5,
        0xd00Bdb70BfC067Ab3dB5395932B45CD9a589a7fc,
        0xdE9D8c2d465669c661672d7945D4d4f5407d22E2
    ];

    // base contracts (vaults, connectors and hooks)
    address[15] baseContracts = [
        0x9354E3822CE6BF77B2761f8922972BB767D771d8,
        0x7F7c594eE170a62d7e7615972831038Cf7d4Fc1A,
        0xe35A32f61C6AA3110Fc72251499B89D51F221C09,
        0xE194f2B41A5dc6Be311aD7811eF391a0ac84687d,
        0xBE32c7765E5432fEbd86043876D5a9c73b1b2Ac2,
        0xca27c3F42092dbC211296651470EF3771B8d4509,
        0xfDF267c43c0C868046c66695c1a85c973418CBFb,
        0x13E2705B19c36aa274a552D6d9FFe5fFfd2e6804,
        0xeFc88792EBbd4561A1495b027590fBCC8EbE1Fac,
        0xc7744d1A93c56a6eE12CCF1F2264641F219528fE,
        0xb7eFF520393c146F857cEeC6f18968b127815C58,
        0x2e7ADd41b5C7eAFBbB298e4AB2EbC158C18737B5,
        0x8de880ecA6B95214C1ECd1556BF1DB4d23f212B5,
        0x7024e1F50e2104f488372894Bbacef1Dfa7bFb98,
        0xb34896F06049891dD5c30E063FCf7A16d3834428
    ];

    // arbitrum contracts (vaults, connectors and hooks)
    address[18] arbitrumContracts = [
        0x36E2DBe085eE4d028fD60f70670f662365d0E978,
        0xeb61Ae531F3a3b06E9da77Ec4AD03B102F5b4eF2,
        0x4b7945796aFe4d2fCe6D271bF7773b5163E1bcC1,
        0x6F855dE562CC9d019757f5F68a15Cd392FF52962,
        0xc5d01939Af7Ce9Ffc505F0bb36eFeDde7920f2dc,
        0x05369D989D9dD9cD6537E667865Ee8157d5EE91B,
        0x4D585D346DFB27b297C37F480a82d4cAB39491Bb,
        0x00A0c9d82B95a17Cdf2D46703F2DcA13EB0E8A94,
        0x47469683AEAD0B5EF2c599ff34d55C3D998393Bf,
        0xC88A469B96A62d4DA14Dc5e23BDBC495D2b15C6B,
        0x755cD5d147036E11c76F1EeffDd94794fC265f0d,
        0xD97E3cD27fb8af306b2CD42A61B7cbaAF044D08D,
        0x7C852c2a3e367453Ce3a68A4D12c313BaD0565e3,
        0x351d8894fB8bfa1b0eFF77bFD9Aab18eA2da8fDd,
        0x70ae312d3f1c9116BF89db833DaDc060D4AD820F,
        0x8bD30d8c5d5cBb5e41Af7B9A4bD654b34772e890,
        0xdf34E61B6e7B9e348713d528fEB019d504d38c1e,
        0x9d46297E4d0fb4D911bDE9746dBb7077d897a908
    ];

    function run() public override {
        super.run();
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address kintoDeployer = vm.addr(deployerPrivateKey);
        bytes32 role = keccak256("RESCUE_ROLE");
        address[] memory contracts = getContracts();

        if (kintoArbitrumSafeAddress == address(0)) revert("Arbitrum Safe address not set");
        if (kintoBaseSafeAddress == address(0)) revert("Base Safe address not set");
        if (kintoMainnetSafeAddress == address(0)) revert("Mainnet Safe address not set");
        address safeAddress = getSafe();

        vm.startBroadcast(deployerPrivateKey);

        // revoke RESCUE_ROLE from deployer
        console2.log("Granting/Revoking RESCUE_ROLE roles...");
        for (uint256 i = 0; i < contracts.length; i++) {
            bool hasRole = AccessControl(contracts[i]).hasRole(role, kintoDeployer);
            if (hasRole) {
                console2.log("- Revoking role from %s on %s", kintoDeployer, contracts[i]);
                AccessControl(contracts[i]).revokeRole(role, kintoDeployer);
            } else {
                console2.log("- Role already revoked from %s on %s", kintoDeployer, contracts[i]);
            }

            hasRole = AccessControl(contracts[i]).hasRole(role, safeAddress);
            if (hasRole) {
                console2.log("- Role already granted to %s on %s", safeAddress, contracts[i]);
            } else {
                console2.log("- Granting role to %s on %s", safeAddress, contracts[i]);
                AccessControl(contracts[i]).grantRole(role, safeAddress);
            }
        }

        // nominate new owner
        console2.log("\nNominating new owners...");
        for (uint256 i = 0; i < contracts.length; i++) {
            console2.log("- Nominating", safeAddress, "as owner of", contracts[i]);
            AccessControl(contracts[i]).nominateOwner(safeAddress);
        }

        vm.stopBroadcast();

        // check roles
        console2.log("\nValidating roles...");
        for (uint256 i = 0; i < contracts.length; i++) {
            AccessControl contractInstance = AccessControl(contracts[i]);
            require(!contractInstance.hasRole(role, kintoDeployer), "Rescue role not revoked");
            require(contractInstance.hasRole(role, safeAddress), "Rescue role not set");
        }

        // validate Safe can claim ownership
        vm.startPrank(safeAddress);
        for (uint256 i = 0; i < contracts.length; i++) {
            AccessControl(contracts[i]).claimOwner();
            require(AccessControl(contracts[i]).owner() == safeAddress, "Ownership not transferred");
        }
    }

    function getSafe() public view returns (address safeAddress) {
        if (block.chainid == 1) {
            safeAddress = kintoMainnetSafeAddress;
        } else if (block.chainid == 42161) {
            safeAddress = kintoArbitrumSafeAddress;
        } else if (block.chainid == 8453) {
            safeAddress = kintoBaseSafeAddress;
        } else {
            revert("Unsupported chain");
        }
    }

    function getContracts() public view returns (address[] memory contracts) {
        if (block.chainid == 1) {
            contracts = new address[](mainnetContracts.length);
            for (uint256 i = 0; i < mainnetContracts.length; i++) {
                contracts[i] = mainnetContracts[i];
            }
        } else if (block.chainid == 42161) {
            contracts = new address[](arbitrumContracts.length);
            for (uint256 i = 0; i < arbitrumContracts.length; i++) {
                contracts[i] = arbitrumContracts[i];
            }
        } else if (block.chainid == 8453) {
            contracts = new address[](baseContracts.length);
            for (uint256 i = 0; i < baseContracts.length; i++) {
                contracts[i] = baseContracts[i];
            }
        } else {
            revert("Unsupported chain");
        }
    }
}

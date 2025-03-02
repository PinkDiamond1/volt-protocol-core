// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "./../utils/Vm.sol";
import {Test} from "../../../../forge-std/src/Test.sol";
import {Volt} from "../../../volt/Volt.sol";
import {Core} from "../../../core/Core.sol";
import {IVolt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract UnitTestCore is DSTest {
    IVolt private volt;
    Core private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    function setUp() public {
        core = getCore();

        volt = core.volt();
    }

    function testGovernorSetsVcon() public {
        vm.prank(addresses.governorAddress);
        core.setVcon(IERC20(addresses.userAddress));

        assertEq(address(core.vcon()), addresses.userAddress);
    }

    function testNonGovernorFailsSettingVcon() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setVcon(IERC20(addresses.userAddress));
    }
}

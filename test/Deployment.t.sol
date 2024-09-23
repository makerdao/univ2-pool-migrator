// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";

import { UniV2PoolMigratorInit } from "deploy/UniV2PoolMigratorInit.sol";

import { UsdsDeploy } from "lib/usds/deploy/UsdsDeploy.sol";
import { UsdsInit, UsdsInstance } from "lib/usds/deploy/UsdsInit.sol";
import { SkyDeploy } from "lib/sky/deploy/SkyDeploy.sol";
import { SkyInit, SkyInstance } from "lib/sky/deploy/SkyInit.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external;
}

interface UniV2FactoryLike {
    function createPair(address, address) external returns (address);
}

interface PoolLike {
    function getReserves() external view returns (uint112, uint112, uint32);
}

contract DeploymentTest is DssTest {
    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant UNIV2_DAI_MKR_PAIR = 0x517F9dD285e75b599234F7221227339478d0FcC8;
    address constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address PAUSE_PROXY;
    address DAI;
    address MKR;
    address USDS;
    address SKY;
    address UNIV2_USDS_SKY_PAIR;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        PAUSE_PROXY = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");

        UsdsInstance memory usdsInst = UsdsDeploy.deploy(address(this), PAUSE_PROXY, ChainlogLike(LOG).getAddress("MCD_JOIN_DAI"));
        SkyInstance  memory  skyInst = SkyDeploy.deploy(address(this), PAUSE_PROXY, ChainlogLike(LOG).getAddress("MCD_GOV"), 24_000);

        vm.startPrank(PAUSE_PROXY);
        UsdsInit.init(dss, usdsInst);
        SkyInit.init(dss, skyInst, 24_000);
        vm.stopPrank();

        DAI  = ChainlogLike(LOG).getAddress("MCD_DAI");
        MKR  = ChainlogLike(LOG).getAddress("MCD_GOV");
        USDS = ChainlogLike(LOG).getAddress("USDS");
        SKY  = ChainlogLike(LOG).getAddress("SKY");

        UNIV2_USDS_SKY_PAIR = UniV2FactoryLike(UNIV2_FACTORY).createPair(USDS, SKY);
    }

    function testSetUp() public {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        uint256 pProxyDaiMkrBalancePrev = GemLike(UNIV2_DAI_MKR_PAIR).balanceOf(PAUSE_PROXY);
        assertGt(pProxyDaiMkrBalancePrev, 0);
        uint256 pProxyUsdsSkyBalancePrev = GemLike(UNIV2_USDS_SKY_PAIR).balanceOf(PAUSE_PROXY);
        assertEq(pProxyUsdsSkyBalancePrev, 0);

        uint256 pProxyDaiBalance = GemLike(DAI).balanceOf(UNIV2_DAI_MKR_PAIR) * pProxyDaiMkrBalancePrev / GemLike(UNIV2_DAI_MKR_PAIR).totalSupply();
        uint256 pProxyMkrBalance = GemLike(MKR).balanceOf(UNIV2_DAI_MKR_PAIR) * pProxyDaiMkrBalancePrev / GemLike(UNIV2_DAI_MKR_PAIR).totalSupply();

        vm.startPrank(PAUSE_PROXY);
        UniV2PoolMigratorInit.init(dss, UNIV2_DAI_MKR_PAIR, UNIV2_USDS_SKY_PAIR);
        vm.stopPrank();

        uint256 pProxyDaiMkrBalanceAft = GemLike(UNIV2_DAI_MKR_PAIR).balanceOf(PAUSE_PROXY);
        assertEq(pProxyDaiMkrBalanceAft, 0);
        uint256 pProxyUsdsSkyBalanceAft = GemLike(UNIV2_USDS_SKY_PAIR).balanceOf(PAUSE_PROXY);
        assertGt(pProxyUsdsSkyBalanceAft, 0);
        // 10**3 == UniswapV2Pair MINIMUM_LIQUIDITY => https://github.com/Uniswap/v2-core/blob/ee547b17853e71ed4e0101ccfd52e70d5acded58/contracts/UniswapV2Pair.sol#L121
        assertEq(pProxyUsdsSkyBalanceAft, GemLike(UNIV2_USDS_SKY_PAIR).totalSupply() - 10**3);

        assertEq(GemLike(USDS).balanceOf(UNIV2_USDS_SKY_PAIR), pProxyDaiBalance);
        assertEq(GemLike(SKY).balanceOf(UNIV2_USDS_SKY_PAIR), pProxyMkrBalance * 24_000);
    }

    function checkPriceSanityCheck(uint256 newPipPrice) public {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);
        address pipMkr = ChainlogLike(LOG).getAddress("PIP_MKR");

        vm.store(address(pipMkr), bytes32(uint256(1)), bytes32(newPipPrice));
        vm.startPrank(PAUSE_PROXY);
        UniV2PoolMigratorInit.init(dss, UNIV2_DAI_MKR_PAIR, UNIV2_USDS_SKY_PAIR);
        vm.stopPrank();
    }

    function testPriceSanityCheck() public {
        (uint256 daiReserve, uint256 mkrReserve, ) = PoolLike(UNIV2_DAI_MKR_PAIR).getReserves();
        uint256 uniPrice = daiReserve * 1e18 / mkrReserve;

        vm.expectRevert("UniV2PoolMigratorInit/sanity-check-2-failed");
        this.checkPriceSanityCheck(uniPrice * 100 / 103);

        vm.expectRevert("UniV2PoolMigratorInit/sanity-check-2-failed");
        this.checkPriceSanityCheck(uniPrice * 100 / 97);

        // No revert
        this.checkPriceSanityCheck(uniPrice);
    }
}

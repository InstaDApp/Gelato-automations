// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;
import {sub, mul, wmul, RAY} from "../vendor/DSMath.sol";
import {IGelatoTaskGenerator} from "../interfaces/IGelatoTaskGenerator.sol";
import {IConnectMaker} from "../interfaces/IConnectMaker.sol";
import {IConnectCompound} from "../interfaces/IConnectCompound.sol";
import {IGelatoGasPriceOracle} from "../interfaces/IGelatoGasPriceOracle.sol";
import {IFlashLoan} from "../interfaces/IFlashLoan.sol";
import {DSAInterface} from "../interfaces/DSAInterface.sol";
import {
    IConnectGelatoProviderPayment
} from "../interfaces/IConnectGelatoProviderPayment.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IVat} from "../interfaces/IVat.sol";

abstract contract Helpers {
    /**
     * @dev Return Maker Connector address.
     */
    function _getConnectMaker() internal pure returns (address) {
        return 0xac02030d8a8F49eD04b2f52C394D3F901A10F8A9;
    }

    /**
     * @dev Return Compound Connector address.
     */
    function _getConnectCompound() internal pure returns (address) {
        return 0x07F81230d73a78f63F0c2A3403AD281b067d28F8;
    }

    /**
     * @dev Return Default Ether address.
     */
    function _getEthAddr() internal pure returns (address) {
        return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

    /**
     * @dev Return Default Ether address.
     */
    function _getDaiTokenAddr() internal pure returns (address) {
        return 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    }

    /**
     * @dev Return Insta pool V2 connector.
     */
    function _getInstaPoolV2Addr() internal pure returns (address) {
        return 0x3150e5A805577366816A1ddc7330c6Ea17070c05;
    }

    /**
     * @dev Return Maker MCD Manager address.
     */
    function _getMcdManager() internal pure returns (address) {
        return 0x5ef30b9986345249bc32d8928B7ee64DE9435E39;
    }
}

abstract contract GelatoHelpers is Helpers {
    // To retrieve when the connector is deployed and replace with the address of the deployed instance
    address public gelatoPaymentConnectorAddr;

    /**
     * @dev Return Gelato Payment Connector.
     */
    function _getConnectGelatoProviderPaymentAddr()
        internal
        view
        returns (address)
    {
        return gelatoPaymentConnectorAddr;
    }

    /**
     * @dev Return Gelato gas price oracle.
     */
    function _getGelatoGasPriceOracle() internal pure returns (address) {
        return 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
    }

    /**
     * @dev Return Gas price.
     */
    function _getGelatoGasPrice() internal view returns (uint256) {
        return
            uint256(
                IGelatoGasPriceOracle(_getGelatoGasPriceOracle()).latestAnswer()
            );
    }
}

abstract contract MakerResolver is GelatoHelpers {
    /**
     * @dev Return Debt in wad of the vault associated to the vaultId.
     */
    function getMakerVaultDebt(uint256 _vaultId)
        public
        view
        returns (uint256 wad)
    {
        IManager cdpManager = _getManager();

        (bytes32 ilk, address urn) = _getVaultData(cdpManager, _vaultId);
        IVat vat = IVat(cdpManager.vat());
        (, uint256 rate, , , ) = vat.ilks(ilk);
        (, uint256 art) = vat.urns(ilk, urn);
        uint256 dai = vat.dai(urn);

        uint256 rad = sub(mul(art, rate), dai);
        wad = rad / RAY;

        wad = mul(wad, RAY) < rad ? wad + 1 : wad;
    }

    /**
     * @dev Return Collateral in wad of the vault associated to the vaultId.
     */
    function getMakerVaultCollateralBalance(uint256 _vaultId)
        public
        view
        returns (uint256)
    {
        IManager cdpManager = _getManager();

        IVat vat = IVat(cdpManager.vat());
        (bytes32 ilk, address urn) = _getVaultData(cdpManager, _vaultId);
        (uint256 ink, ) = vat.urns(ilk, urn);

        return ink;
    }

    function _getVaultData(IManager cdpManager, uint256 vault)
        internal
        view
        returns (bytes32 ilk, address urn)
    {
        ilk = cdpManager.ilks(vault);
        urn = cdpManager.urns(vault);
    }

    function _getManager() internal pure returns (IManager) {
        return IManager(_getMcdManager());
    }
}

abstract contract DebtBridgeFromMakerForFullRefinanceResolver is MakerResolver {
    function execPayloadForFullRefinanceFromMakerToMaker(
        uint256 _vaultId,
        address _token,
        string memory _colType,
        address _provider
    ) public view virtual returns (address, bytes memory);

    function execPayloadForFullRefinanceFromMakerToCompound(
        uint256 _vaultId,
        address _token,
        address _provider
    ) public view virtual returns (address, bytes memory);

    /// @notice Generate Data for calling execPayloadForFullRefinanceFromMakerToMaker via a static call.
    /// @param _vaultId Id of the unsafe vault of the client.
    /// @param _token  vault's col token address .
    /// @param _colType colType of the new vault, exemple : ETH-B, ETH-A.
    /// @param _provider address of the paying provider.
    /// @return a call data for a static call of execPayloadForFullRefinanceFromMakerToMaker.
    function getDebtBridgeFullRefinanceMakerToMakerData(
        uint256 _vaultId,
        address _token,
        string memory _colType,
        address _provider
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                this.execPayloadForFullRefinanceFromMakerToMaker.selector,
                _vaultId,
                _token,
                _colType,
                _provider
            );
    }

    /// @notice Generate Data for calling execPayloadForFullRefinanceFromMakerToCompound via a static call.
    /// @param _vaultId Id of the unsafe vault of the client.
    /// @param _token  vault's col token address .
    /// @param _provider address of the paying provider.
    /// @return a call data for a static call of execPayloadForFullRefinanceFromMakerToMaker.
    function getDebtBridgeFullRefinanceMakerToCompoundData(
        uint256 _vaultId,
        address _token,
        address _provider
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                this.execPayloadForFullRefinanceFromMakerToCompound.selector,
                _vaultId,
                _token,
                _provider
            );
    }
}

/// @title DebtBridgeFromMakerForFullRefinance
/// @notice Task Generator contract that generate task for a full refinancing from maker protocol to another protocol (can be Maker).
/// @author Gelato Team
contract DebtBridgeFromMakerForFullRefinance is
    DebtBridgeFromMakerForFullRefinanceResolver
{
    uint256 public constant GAS_COST = 1490779 + (14908 * 2); // 1933080 + ~2% (Estimated Value)

    constructor(address _gelatoPaymentConnectorAddr) {
        gelatoPaymentConnectorAddr = _gelatoPaymentConnectorAddr;
    }

    /// @notice Generate Task for a full refinancing between Maker to Compound.
    /// @param _vaultId Id of the unsafe vault of the client.
    /// @param _token  vault's col token address .
    /// @param _provider address of the paying provider.
    /// @return a target the flashloan contract address and the corresponding call data.
    function execPayloadForFullRefinanceFromMakerToCompound(
        uint256 _vaultId,
        address _token,
        address _provider
    ) public view override returns (address, bytes memory) {
        address target = _getInstaPoolV2Addr();
        address connectMaker = _getConnectMaker();
        address connectCompound = _getConnectCompound();
        address daiToken = _getDaiTokenAddr();

        uint256 wDaiDebtToMove = getMakerVaultDebt(_vaultId);
        uint256 wColToWithdrawFromMaker = getMakerVaultCollateralBalance(
            _vaultId
        );
        uint256 gasFeesPaidFromCol = _getGelatoProviderFees();

        address[] memory targets = new address[](6);
        targets[0] = connectMaker; // payback
        targets[1] = connectMaker; // withdraw
        targets[2] = connectCompound; // deposit
        targets[3] = connectCompound; // borrow
        targets[4] = _getConnectGelatoProviderPaymentAddr();
        targets[5] = target;

        bytes[] memory datas = new bytes[](6);
        datas[0] = _encodedDataForPayBackMakerVault(
            _vaultId,
            uint256(-1),
            0,
            0
        );
        datas[1] = _encodedDataForWithdrawMakerVault(
            _vaultId,
            uint256(-1),
            0,
            0
        );
        datas[2] = _encodedDataForDepositOnCompound(
            _token,
            sub(wColToWithdrawFromMaker, gasFeesPaidFromCol),
            0,
            0
        );
        datas[3] = _encodedDataForBorrowDaiOnCompound(
            daiToken,
            wDaiDebtToMove,
            0,
            0
        );
        datas[4] = _encodeDataForPayingProvider(
            _provider,
            _token,
            gasFeesPaidFromCol,
            0,
            0
        );
        datas[5] = _encodeDataForPayingBackDyDx(daiToken, wDaiDebtToMove, 0, 0);

        bytes memory flashloanCallData = abi.encode(targets, datas);
        bytes memory callData = abi.encodeWithSelector(
            IFlashLoan.flashBorrowAndCast.selector,
            daiToken,
            wDaiDebtToMove,
            0,
            flashloanCallData
        );

        return (target, callData);
    }

    /// @notice Generate Task for a full refinancing between Maker (exemple : ETH-A) to Maker (exemple: ETH-B).
    /// @param _vaultId Id of the unsafe vault of the client.
    /// @param _token  vault's col token address .
    /// @param _colType colType of the new vault, exemple : ETH-B, ETH-A.
    /// @param _provider address of the paying provider.
    /// @return a target the flashloan contract address and the corresponding call data.
    function execPayloadForFullRefinanceFromMakerToMaker(
        uint256 _vaultId,
        address _token,
        string memory _colType,
        address _provider
    ) public view override returns (address, bytes memory) {
        address target = _getInstaPoolV2Addr();
        address connectMaker = _getConnectMaker();
        address daiToken = _getDaiTokenAddr();

        uint256 wDaiDebtToMove = getMakerVaultDebt(_vaultId);
        uint256 wColToWithdrawFromMaker = getMakerVaultCollateralBalance(
            _vaultId
        );
        uint256 gasFeesPaidFromCol = _getGelatoProviderFees();

        address[] memory targets = new address[](7);
        targets[0] = connectMaker; // payback
        targets[1] = connectMaker; // withdraw
        targets[2] = connectMaker; // open ETH-B vault
        targets[3] = connectMaker; // deposit
        targets[4] = connectMaker; // borrow
        targets[5] = _getConnectGelatoProviderPaymentAddr();
        targets[6] = target;

        bytes[] memory datas = new bytes[](7);
        datas[0] = _encodedDataForPayBackMakerVault(
            _vaultId,
            uint256(-1),
            0,
            0
        );
        datas[1] = _encodedDataForWithdrawMakerVault(
            _vaultId,
            uint256(-1),
            0,
            0
        );
        datas[2] = _encodedDataForOpenAMakerVault(_colType);
        datas[3] = _encodedDataForDepositOnMakerVault(
            0,
            sub(wColToWithdrawFromMaker, gasFeesPaidFromCol),
            0,
            0
        );
        datas[4] = _encodedDataForBorrowDaiOnMakerVault(
            0,
            wDaiDebtToMove,
            0,
            0
        );
        datas[5] = _encodeDataForPayingProvider(
            _provider,
            _token,
            gasFeesPaidFromCol,
            0,
            0
        );
        datas[6] = _encodeDataForPayingBackDyDx(daiToken, wDaiDebtToMove, 0, 0);

        bytes memory flashloanCallData = abi.encode(targets, datas);
        bytes memory callData = abi.encodeWithSelector(
            IFlashLoan.flashBorrowAndCast.selector,
            daiToken,
            wDaiDebtToMove,
            0,
            flashloanCallData
        );

        return (target, callData);
    }

    function _encodedDataForPayBackMakerVault(
        uint256 _vaultId,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConnectMaker.payback.selector,
                _vaultId,
                _amt,
                _getId,
                _setId
            );
    }

    function _encodedDataForWithdrawMakerVault(
        uint256 _vaultId,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConnectMaker.withdraw.selector,
                _vaultId,
                _amt,
                _getId,
                _setId
            );
    }

    function _encodedDataForOpenAMakerVault(string memory _colType)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(IConnectMaker.open.selector, _colType);
    }

    function _encodedDataForDepositOnMakerVault(
        uint256 _vaultId,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConnectMaker.deposit.selector,
                _vaultId,
                _amt,
                _getId,
                _setId
            );
    }

    function _encodedDataForDepositOnCompound(
        address _token,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConnectCompound.deposit.selector,
                _token,
                _amt,
                _getId,
                _setId
            );
    }

    function _encodedDataForBorrowDaiOnMakerVault(
        uint256 _vaultId,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConnectMaker.borrow.selector,
                _vaultId,
                _amt,
                _getId,
                _setId
            );
    }

    function _encodedDataForBorrowDaiOnCompound(
        address _token,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConnectCompound.borrow.selector,
                _token,
                _amt,
                _getId,
                _setId
            );
    }

    function _encodeDataForPayingProvider(
        address _provider,
        address _token,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConnectGelatoProviderPayment.payProvider.selector,
                _provider,
                _token,
                _amt,
                _getId,
                _setId
            );
    }

    function _encodeDataForPayingBackDyDx(
        address _token,
        uint256 _amt,
        uint256 _getId,
        uint256 _setId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IFlashLoan.flashPayback.selector,
                _token,
                _amt,
                _getId,
                _setId
            );
    }

    function _getGelatoProviderFees()
        internal
        view
        virtual
        returns (uint256 gasCost)
    {
        gasCost = mul(GAS_COST, _getGelatoGasPrice());
    }
}

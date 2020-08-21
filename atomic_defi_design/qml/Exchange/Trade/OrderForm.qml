import QtQuick 2.14
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import QtGraphicalEffects 1.0

import "../../Components"
import "../../Constants"

FloatingBackground {
    id: root

    property alias field: input_volume.field
    property alias price_field: input_price.field
    property bool is_sell_form: false
    property alias column_layout: form_layout
    property string total_amount: "0"

    function getFiatText(v, ticker) {
        return General.formatFiat('', v === '' ? 0 : API.get().get_fiat_from_amount(ticker, v), API.get().settings_pg.current_fiat) + " " +  General.cex_icon
    }

    function getVolume() {
        return input_volume.field.text === '' ? '0' :  input_volume.field.text
    }

    function fieldsAreFilled() {
        return input_volume.field.text !== '' && input_price.field.text !== ''
    }

    function hasEthFees() {
        return General.isFilled(curr_trade_info.erc_fees) && parseFloat(curr_trade_info.erc_fees) > 0
    }

    function hasEnoughEthForFees() {
        return General.isEthEnabled() && API.get().do_i_have_enough_funds("ETH", curr_trade_info.erc_fees)
    }

    function higherThanMinTradeAmount() {
        if(input_volume.field.text === '') return false
        return parseFloat(is_sell_form ? input_volume.field.text : total_amount) >= General.getMinTradeAmount()
    }

    function isValid() {
        let valid = true

        if(valid) valid = fieldsAreFilled()
        if(valid) valid = higherThanMinTradeAmount()

        if(valid) valid = !notEnoughBalance()
        if(valid) valid = API.get().do_i_have_enough_funds(base_ticker, General.formatDouble(getNeededAmountToSpend(input_volume.field.text)))
        if(valid && hasEthFees()) valid = hasEnoughEthForFees()

        return valid
    }

    function getMaxBalance() {
        if(General.isFilled(base_ticker))
            return API.get().get_balance(base_ticker)

        return "0"
    }

    function getMaxVolume() {
        // base in this orderbook is always the left side, so when it's buy, we want the right side balance (rel in the backend)
        const value = is_sell_form ? API.get().trading_pg.orderbook.base_max_taker_vol.decimal :
                                  API.get().trading_pg.orderbook.rel_max_taker_vol.decimal

        if(General.isFilled(value))
            return value

        return getMaxBalance()
    }

    function getMaxTradableVolume(set_as_current) {
        // set_as_current should be true if input_volume is updated
        // if it's called for cap check, it should be false because that's not the current input_volume

        const base = base_ticker
        const rel = rel_ticker
        const amount = getMaxVolume()

        if(base === '' || rel === '') return 0

        const info = getTradeInfo(base, rel, amount, set_as_current)
        const my_amt = parseFloat(valid_trade_info ? info.input_final_value : amount)
        if(is_sell_form) return my_amt

        // If it's buy side, then volume input needs to be calculated with the current price
        const price = parseFloat(getCurrentPrice())
        return price === 0 ? 0 : my_amt / price
    }

    function reset(is_base) {
        input_price.field.text = ''
        input_volume.field.text = ''
    }

    function capVolume() {
        if(inCurrentPage() && input_volume.field.acceptableInput) {
            // If price is 0 at buy side, don't cap it to 0, let the user edit
            if(!is_sell_form && General.isZero(getCurrentPrice()))
                return false

            const input_volume_value = parseFloat(input_volume.field.text)
            let amt = input_volume_value

            // Cap with balance
            const cap_with_fees = getMaxTradableVolume(false)
            if(amt > cap_with_fees)
                amt = cap_with_fees

            // Cap with order volume
            if(orderIsSelected()) {
                const order_buy_volume = parseFloat(preffered_order.volume)
                if(amt > order_buy_volume)
                    amt = order_buy_volume
            }

            // Set the field
            if(amt !== input_volume_value) {
                input_volume.field.text = General.formatDouble(amt)
                return true
            }
        }

        return false
    }

    function getNeededAmountToSpend(volume) {
        volume = parseFloat(volume)
        if(is_sell_form) return volume
        else        return volume * parseFloat(getCurrentPrice())
    }

    function notEnoughBalance() {
        return parseFloat(getMaxVolume()) < General.getMinTradeAmount()
    }

    function onInputChanged() {
        if(capVolume()) updateTradeInfo()

        // Recalculate total amount
        const price = parseFloat(getCurrentPrice())
        const base_volume = parseFloat(getVolume())
        const new_receive_text = General.formatDouble(base_volume * price)
        if(total_amount !== new_receive_text)
            total_amount = new_receive_text

        // Update the new fees, input_volume might be changed
        updateTradeInfo()
    }

    implicitHeight: form_layout.height

    ColumnLayout {
        id: form_layout
        width: parent.width

        ColumnLayout {
            Layout.alignment: Qt.AlignTop

            Layout.fillWidth: true
            spacing: 15

            // Top Line
            RowLayout {
                id: top_line
                spacing: 20
                Layout.topMargin: parent.spacing
                Layout.leftMargin: parent.spacing
                Layout.rightMargin: Layout.leftMargin
                Layout.alignment: Qt.AlignHCenter

                DefaultButton {
                    Layout.fillWidth: true
                    font.pixelSize: Style.textSize
                    text: API.get().settings_pg.empty_string + (qsTr("Sell %1", "TICKER").arg(left_ticker))
                    color: sell_mode ? Style.colorButtonEnabled.default : Style.colorButtonDisabled.default
                    colorTextEnabled: sell_mode ? Style.colorButtonEnabled.danger : Style.colorButtonDisabled.danger
                    font.weight: Font.Bold
                    onClicked: sell_mode = true
                }
                DefaultButton {
                    Layout.fillWidth: true
                    font.pixelSize: Style.textSize
                    text: API.get().settings_pg.empty_string + (qsTr("Buy %1", "TICKER").arg(left_ticker))
                    color: sell_mode ? Style.colorButtonDisabled.default : Style.colorButtonEnabled.default
                    colorTextEnabled: sell_mode ? Style.colorButtonDisabled.primary : Style.colorButtonEnabled.primary
                    font.weight: Font.Bold
                    onClicked: sell_mode = false
                }
            }


            HorizontalLine {
                Layout.fillWidth: true
            }


            Item {
                Layout.fillWidth: true
                Layout.leftMargin: top_line.Layout.leftMargin
                Layout.rightMargin: top_line.Layout.rightMargin
                Layout.bottomMargin: input_volume.field.font.pixelSize
                height: input_volume.height

                AmountFieldWithInfo {
                    id: input_price
                    width: parent.width
                    enabled: input_volume.field.enabled

                    field.left_text: API.get().settings_pg.empty_string + (qsTr("Price"))
                    field.right_text: right_ticker

                    field.onTextChanged: {
                        onInputChanged()
                    }

                    function resetPrice() {
                        if(orderIsSelected()) resetPreferredPrice()
                    }

                    field.onPressed: resetPrice()
                    field.onFocusChanged: {
                        if(field.activeFocus) resetPrice()
                    }
                }

                DefaultText {
                    id: price_usd_value
                    anchors.right: input_price.right
                    anchors.top: input_price.bottom
                    anchors.topMargin: 7

                    text_value: getFiatText(input_price.field.text, right_ticker)
                    font.pixelSize: input_price.field.font.pixelSize

                    CexInfoTrigger {}
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.leftMargin: top_line.Layout.leftMargin
                Layout.rightMargin: top_line.Layout.rightMargin
                Layout.bottomMargin: input_volume.field.font.pixelSize
                height: input_volume.height

                AmountFieldWithInfo {
                    id: input_volume
                    width: parent.width

                    field.left_text: API.get().settings_pg.empty_string + (qsTr("Volume"))
                    field.right_text: left_ticker
                    field.placeholderText: API.get().settings_pg.empty_string + (is_sell_form ? qsTr("Amount to sell") : qsTr("Amount to receive"))
                    field.onTextChanged: {
                        const before_checks = field.text
                        onInputChanged()
                        const after_checks = field.text

                        // Update slider only if the value is not from slider, or value got corrected here
                        if(before_checks !== after_checks || !input_volume_slider.updating_text_field) {
                            input_volume_slider.updating_from_text_field = true
                            input_volume_slider.value = parseFloat(field.text)
                            input_volume_slider.updating_from_text_field = false
                        }
                    }
                }

                DefaultText {
                    anchors.right: input_volume.right
                    anchors.top: input_volume.bottom
                    anchors.topMargin: price_usd_value.anchors.topMargin

                    text_value: getFiatText(input_volume.field.text, left_ticker)
                    font.pixelSize: input_volume.field.font.pixelSize

                    CexInfoTrigger {}
                }
            }

            Slider {
                id: input_volume_slider
                function getRealValue() {
                    return input_volume_slider.position * (input_volume_slider.to - input_volume_slider.from)
                }

                enabled: input_volume.field.enabled
                property bool updating_from_text_field: false
                property bool updating_text_field: false
                readonly property int precision: General.getRecommendedPrecision(to)
                visible: is_sell_form
                Layout.fillWidth: true
                Layout.leftMargin: top_line.Layout.leftMargin
                Layout.rightMargin: top_line.Layout.rightMargin
                Layout.bottomMargin: top_line.Layout.rightMargin*0.5
                from: 0
                to: Math.max(0, parseFloat(getMaxVolume()))
                stepSize: 1/Math.pow(10, precision)
                live: false

                onValueChanged: {
                    if(updating_from_text_field) return

                    if(pressed) {
                        updating_text_field = true
                        input_volume.field.text = General.formatDouble(value)
                        updating_text_field = false
                    }
                }

                DefaultText {
                    visible: parent.pressed
                    anchors.horizontalCenter: parent.handle.horizontalCenter
                    anchors.bottom: parent.handle.top

                    text_value: General.formatDouble(input_volume_slider.getRealValue(), input_volume_slider.precision)
                    font.pixelSize: input_volume.field.font.pixelSize
                }

                DefaultText {
                    anchors.left: parent.left
                    anchors.top: parent.bottom

                    text_value: API.get().settings_pg.empty_string + (qsTr("Min"))
                    font.pixelSize: input_volume.field.font.pixelSize
                }
                DefaultText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom

                    text_value: API.get().settings_pg.empty_string + (qsTr("Half"))
                    font.pixelSize: input_volume.field.font.pixelSize
                }
                DefaultText {
                    anchors.right: parent.right
                    anchors.top: parent.bottom

                    text_value: API.get().settings_pg.empty_string + (qsTr("Max"))
                    font.pixelSize: input_volume.field.font.pixelSize
                }
            }


            // Fees
            InnerBackground {
                radius: 100
                id: bg
                Layout.fillWidth: true
                Layout.leftMargin: top_line.Layout.leftMargin
                Layout.rightMargin: top_line.Layout.rightMargin

                content: RowLayout {
                    width: bg.width
                    height: tx_fee_text.font.pixelSize * 4

                    ColumnLayout {
                        id: fees
                        visible: valid_trade_info && !General.isZero(getVolume())

                        Layout.leftMargin: 10
                        Layout.rightMargin: Layout.leftMargin
                        Layout.alignment: Qt.AlignLeft

                        DefaultText {
                            id: tx_fee_text
                            text_value: API.get().settings_pg.empty_string + ((qsTr('Transaction Fee') + ': ' + General.formatCrypto("", curr_trade_info.tx_fee, curr_trade_info.is_ticker_of_fees_eth ? "ETH" : base_ticker)) +
                                                                    // ETH Fees
                                                                    (hasEthFees() ? " + " + General.formatCrypto("", curr_trade_info.erc_fees, 'ETH') : '') +

                                                                  // Fiat part
                                                                  (" ("+
                                                                      getFiatText(!hasEthFees() ? curr_trade_info.tx_fee : General.formatDouble((parseFloat(curr_trade_info.tx_fee) + parseFloat(curr_trade_info.erc_fees))),
                                                                                  curr_trade_info.is_ticker_of_fees_eth ? 'ETH' : base_ticker)
                                                                   +")")


                                                                  )
                            font.pixelSize: Style.textSizeSmall1

                            CexInfoTrigger {}
                        }

                        DefaultText {
                            text_value: API.get().settings_pg.empty_string + (qsTr('Trading Fee') + ': ' + General.formatCrypto("", curr_trade_info.trade_fee, base_ticker) +

                                                                  // Fiat part
                                                                  (" ("+
                                                                      getFiatText(curr_trade_info.trade_fee, base_ticker)
                                                                   +")")
                                                                  )
                            font.pixelSize: tx_fee_text.font.pixelSize

                            CexInfoTrigger {}
                        }
                    }


                    DefaultText {
                        visible: !fees.visible

                        text_value: API.get().settings_pg.empty_string + (!visible ? "" :
                                                    notEnoughBalance() ? (qsTr('Minimum fee') + ":     " + General.formatCrypto("", General.formatDouble(parseFloat(getMaxBalance()) - parseFloat(getMaxVolume())), base_ticker))
                                                                       : qsTr('Fees will be calculated'))
                        Layout.alignment: Qt.AlignCenter
                        font.pixelSize: tx_fee_text.font.pixelSize
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignBottom
            Layout.topMargin: 5
            Layout.fillWidth: true
            Layout.leftMargin: top_line.Layout.rightMargin
            Layout.rightMargin: Layout.leftMargin
            Layout.bottomMargin: layout_margin

            ColumnLayout {
                Layout.alignment: Qt.AlignLeft

                DefaultText {
                    text_value: API.get().settings_pg.empty_string + (qsTr("Total") + ": " + General.formatCrypto("", total_amount, right_ticker))
                    font.pixelSize: Style.textSizeSmall3
                }

                DefaultText {
                    text_value: getFiatText(total_amount, right_ticker)
                    font.pixelSize: input_price.field.font.pixelSize

                    CexInfoTrigger {}
                }
            }

            // Trade button
            DefaultButton {
                Layout.alignment: Qt.AlignRight
                Layout.fillWidth: true
                Layout.leftMargin: 30

                button_type: is_sell_form ? "danger" : "primary"

                width: 170

                text: API.get().settings_pg.empty_string + (qsTr("Start Swap"))
                font.bold: true
                enabled: valid_trade_info && !notEnoughBalanceForFees() && isValid()
                onClicked: confirm_trade_modal.open()
            }
        }

        ColumnLayout {
            spacing: parent.spacing
            visible: errors.text_value !== ""

            Layout.alignment: Qt.AlignBottom
            Layout.fillWidth: true
            Layout.bottomMargin: layout_margin

            HorizontalLine {
                Layout.fillWidth: true
                Layout.bottomMargin: layout_margin
            }

            // Show errors
            DefaultText {
                id: errors
                Layout.leftMargin: top_line.Layout.rightMargin
                Layout.rightMargin: Layout.leftMargin
                Layout.fillWidth: true

                font.pixelSize: Style.textSizeSmall4
                color: Style.colorRed

                text_value: API.get().settings_pg.empty_string + (
                                // Balance check can be done without price too, prioritize that for sell
                                notEnoughBalance() ? (qsTr("Tradable (after fees) %1 balance is lower than minimum trade amount").arg(base_ticker) + " : " + General.getMinTradeAmount()) :

                                // Fill the price field
                                General.isZero(getCurrentPrice()) ? (qsTr("Please fill the price field")) :

                                // Fill the volume field
                                General.isZero(getCurrentForm().getVolume()) ? (qsTr("Please fill the volume field")) :

                               // Trade amount is lower than the minimum
                               (getCurrentForm().fieldsAreFilled() && !getCurrentForm().higherThanMinTradeAmount()) ? ((qsTr("Volume is lower than minimum trade amount")) + " : " + General.getMinTradeAmount()) :

                                // Fields are filled, fee can be checked
                                notEnoughBalanceForFees() ?
                                    (qsTr("Not enough balance for the fees. Need at least %1 more", "AMT TICKER").arg(General.formatCrypto("", curr_trade_info.amount_needed, base_ticker))) :

                                // Not enough ETH for fees
                                (getCurrentForm().hasEthFees() && !getCurrentForm().hasEnoughEthForFees()) ? (qsTr("Not enough ETH for the transaction fee")) : ""
                          )
            }
        }
    }
}

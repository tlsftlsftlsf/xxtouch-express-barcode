-- ==============================================================================
-- 脚本名称: SingleBarcodeFloat.lua
-- 项目说明: XXTouch 屏幕快递单号识别与 CODE128 悬浮窗扫码 (方案 A 交互版)
-- 适用环境: XXTouch / XXTouch Elite (iOS)
-- 编码格式: UTF-8 (无 BOM)
-- ==============================================================================

screen.init(0)
nLog("========== 开始提取单号并弹出 CODE128 条码悬浮窗 ==========")

local PATTERNS = {
    "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
    "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
    "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
    "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
    "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
    "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
    "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
    "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
    "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
    "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
    "114131", "311141", "411131", "211412", "211214", "211232", "2331112"
}

local function encode_code128_auto(text)
    local codes = {}
    local is_numeric = text:match("^%d+$") ~= nil

    if is_numeric and #text >= 2 then
        table.insert(codes, 105)
        local pairs_count = math.floor(#text / 2)
        for i = 1, pairs_count do
            local start_i = (i - 1) * 2 + 1
            table.insert(codes, tonumber(text:sub(start_i, start_i + 1)))
        end
        if #text % 2 ~= 0 then
            table.insert(codes, 100)
            local last_ch = text:sub(#text, #text)
            table.insert(codes, last_ch:byte() - 32)
        end
    else
        table.insert(codes, 104)
        for i = 1, #text do
            table.insert(codes, text:byte(i) - 32)
        end
    end

    local sum = codes[1]
    for i = 2, #codes do
        sum = sum + (i - 1) * codes[i]
    end
    table.insert(codes, sum % 103)
    table.insert(codes, 106)

    local bits = {}
    for _, code in ipairs(codes) do
        local pat = PATTERNS[code + 1]
        local is_bar = true
        for j = 1, #pat do
            local w = tonumber(pat:sub(j, j))
            for _ = 1, w do
                table.insert(bits, is_bar and 1 or 0)
            end
            is_bar = not is_bar
        end
    end
    return bits
end

local function show_styled_float_window(bits, tracking_no)
    local rects = {}
    for i, bit in ipairs(bits) do
        if bit == 1 then
            table.insert(rects, string.format('<rect x="%d" y="0" width="1" height="120" fill="#000"/>', i - 1))
        end
    end

    local total_modules = #bits
    local html = string.format([[
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
            * { box-sizing: border-box; }
            html, body {
                margin: 0; padding: 0;
                width: 100%%; height: 100%%;
                background: #ffffff;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
                user-select: none;
                -webkit-user-select: none;
            }
            .barcode-wrap {
                width: 88%%;
                padding-top: 6px;
            }
            svg {
                width: 100%%;
                height: 110px;
                display: block;
            }
            .label {
                font-size: 21px;
                color: #222222;
                letter-spacing: 2px;
                margin-top: 14px;
                text-align: center;
                font-weight: 400;
            }
        </style>
    </head>
    <body onclick="window.location.href='xxtouch://close'">
        <div class="barcode-wrap">
            <svg viewBox="0 0 %d 120" preserveAspectRatio="none">
                <rect width="100%%" height="100%%" fill="#fff"/>
                %s
            </svg>
        </div>
        <div class="label">%s</div>
    </body>
    </html>
    ]], total_modules, table.concat(rects), tracking_no)

    webview.show {
        id = 200,
        x = 15,
        y = 180,
        width = 345,
        height = 190,
        corner_radius = 8,
        alpha = 1.0,
        can_drag = true,
        html = html
    }
end

local function main()
    local texts = screen.ocr_text {}
    if not texts or #texts == 0 then return end

    for _, text in ipairs(texts) do
        for token in text:gmatch("[A-Za-z0-9]+") do
            local len = #token
            if len >= 10 and len <= 18 then
                local _, digit_count = token:gsub("%d", "")
                if digit_count >= 6 then
                    local is_phone = (len == 11 and token:match("^1[3-9]%d%d%d%d%d%d%d%d%d$") ~= nil)
                    local is_id_card = (len == 18 and token:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d[%dXx]$") ~= nil)

                    if not is_phone and not is_id_card then
                        pasteboard.write(token)
                        local bits = encode_code128_auto(token)
                        show_styled_float_window(bits, token)
                        nLog("已展示单号条形码: " .. token)
                        return
                    end
                end
            end
        end
    end
end

pcall(main)

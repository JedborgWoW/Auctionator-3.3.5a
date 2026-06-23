-- WotLK 3.3.5a compatibility: ColorMixin / CreateColor
--
-- Added to retail in Legion; absent on 3.3.5a. Auctionator uses CreateColor and
-- color:WrapTextInColorCode(...) for coloured text.

if not ColorMixin then
  ColorMixin = {}

  function ColorMixin:OnLoad(r, g, b, a)
    self:SetRGBA(r, g, b, a)
  end

  function ColorMixin:IsEqualTo(other)
    return self.r == other.r
      and self.g == other.g
      and self.b == other.b
      and self.a == other.a
  end

  function ColorMixin:GetRGB()
    return self.r, self.g, self.b
  end

  function ColorMixin:GetRGBAsBytes()
    return self.r * 255, self.g * 255, self.b * 255
  end

  function ColorMixin:GetRGBA()
    return self.r, self.g, self.b, self.a
  end

  function ColorMixin:GetRGBABytes()
    return self.r * 255, self.g * 255, self.b * 255, (self.a or 1) * 255
  end

  function ColorMixin:SetRGBA(r, g, b, a)
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  end

  function ColorMixin:SetRGB(r, g, b)
    self:SetRGBA(r, g, b, nil)
  end

  function ColorMixin:GenerateHexColor()
    return string.format("ff%.2x%.2x%.2x",
      Clamp(Round(self.r * 255), 0, 255),
      Clamp(Round(self.g * 255), 0, 255),
      Clamp(Round(self.b * 255), 0, 255))
  end

  function ColorMixin:GenerateHexColorMarkup()
    return "|c" .. self:GenerateHexColor()
  end

  function ColorMixin:WrapTextInColorCode(text)
    return string.format("|c%s%s|r", self:GenerateHexColor(), text)
  end
end

if not CreateColor then
  function CreateColor(r, g, b, a)
    local color = CreateFromMixins(ColorMixin)
    color:OnLoad(r, g, b, a)
    return color
  end
end

-- Common colour globals as ColorMixin instances (3.3.5a has the *_FONT_COLOR
-- tables as plain {r,g,b} without the mixin methods). Only (re)defined when the
-- mixin method is missing so we do not stomp a native ColorMixin instance.
local function EnsureColor(name, r, g, b, a)
  local existing = _G[name]
  if type(existing) == "table" and existing.WrapTextInColorCode then
    return
  end
  if type(existing) == "table" and existing.r then
    r, g, b, a = existing.r, existing.g, existing.b, existing.a or 1
  end
  _G[name] = CreateColor(r, g, b, a or 1)
end

EnsureColor("WHITE_FONT_COLOR", 1, 1, 1)
EnsureColor("NORMAL_FONT_COLOR", 1.0, 0.82, 0.0)
EnsureColor("HIGHLIGHT_FONT_COLOR", 1, 1, 1)
EnsureColor("RED_FONT_COLOR", 1, 0.1, 0.1)
EnsureColor("GREEN_FONT_COLOR", 0.1, 1, 0.1)
EnsureColor("GRAY_FONT_COLOR", 0.5, 0.5, 0.5)
EnsureColor("LIGHTYELLOW_FONT_COLOR", 1, 1, 0.6)
EnsureColor("DISABLED_FONT_COLOR", 0.5, 0.5, 0.5)
EnsureColor("ERROR_COLOR", 1, 0.1, 0.1)

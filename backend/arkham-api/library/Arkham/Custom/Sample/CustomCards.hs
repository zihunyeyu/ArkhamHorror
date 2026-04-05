module Arkham.Custom.Sample.CustomCards where

import Arkham.Asset.Cards.Import


-- =================Assets=================

customCardsTest1 :: CardDef
customCardsTest1 = (asset "900001" "名枪 安倍切" 2 Guardian)
  { cdSkills = [#combat, #willpower]
  , cdCardTraits = setFromList [Item, Weapon, Firearm]
  , cdSlots = [#hand]
  , cdUses = uses Ammo 2
  }

-- =================Events=================

-- 求生者
-- customCardsSurvivor :: CardDef
-- customCardsSurvivor = (event "900002" "Survivor" 0 Rogue)
--   { cdSkills = [#wild, #wild]
--   , cdCardTraits = singleton Spirit
--   , cdFastWindow = Just $ DealtDamageOrHorror #when (SourceIsCancelable AnySource) You
--   }
module Arkham.Asset.Assets.CustomCardsTest1 (customCardsTest1) where

import Arkham.Ability
import Arkham.Asset.Cards qualified as Cards
import Arkham.Asset.Import.Lifted
import Arkham.Helpers.SkillTest
import Arkham.Investigator.Types (Field (..))
import Arkham.Matcher
import Arkham.Message.Lifted.Choose
import Arkham.Modifier
import Arkham.I18n
import Arkham.Projection (field)

newtype CustomCardsTest1 = CustomCardsTest1 AssetAttrs
  deriving anyclass (IsAsset, HasModifiersFor)
  deriving newtype (Show, Eq, ToJSON, FromJSON, Entity)

customCardsTest1 :: AssetCard CustomCardsTest1
customCardsTest1 = asset CustomCardsTest1 Cards.customCardsTest1

instance HasAbilities CustomCardsTest1 where
  getAbilities (CustomCardsTest1 a) =
    [ -- 补给阶段能力：如果没有子弹，花费1资源放置1子弹
      restricted a 1 (ControlsThis)
        $ triggered 
        (PhaseBegins #when #upkeep)
        Free
    , -- 战斗能力：花费1子弹攻击，+1技能值，+1伤害
      restricted a 2 ControlsThis
        $ fightAction (assetUseCost a #ammo 1)
    ]

instance RunMessage CustomCardsTest1 where
  runMessage msg a@(CustomCardsTest1 attrs) = runQueueT $ case msg of
    -- 补给阶段能力处理
    UseThisAbility iid (isSource attrs -> True) 1 -> do
      let n = attrs.use #ammo
      resources <- field InvestigatorResources iid
      when (n == 0 && resources >= 1) do
        chooseOneM iid do
          labeled "花费1资源，放置1子弹" do
            spendResources iid 1
            addUses (attrs.ability 1) attrs #ammo 1
          labeled "不触发" $ pure ()
      pure a
    -- 战斗能力处理
    UseThisAbility iid (isSource attrs -> True) 2 -> do
      sid <- getRandom
      -- 记录当前攻击的敌人，用于失败后的第二次攻击
      skillTestModifiers sid (attrs.ability 2) iid [SkillModifier #combat 1, DamageDealt 1]
      chooseFightEnemy sid iid (attrs.ability 2)
      pure a

    FailedThisSkillTest iid (isAbilitySource attrs 2 -> True) -> do
      withSkillTest \stid -> do
        sid <- getRandom
        let ammoCount = attrs.use #ammo
        when (ammoCount >= 1) do
          chooseOneM iid do
            withI18n labeled' "skip" nothing
            labeled "再次花费1子弹，自动成功攻击该敌人" do
              removeTokens (attrs.ability 2) attrs #ammo 1
              push $ RepeatSkillTest sid stid
              skillTestModifier sid (attrs.ability 1) sid SkillTestAutomaticallySucceeds
      pure a
    _ -> CustomCardsTest1 <$> liftRunMessage msg attrs

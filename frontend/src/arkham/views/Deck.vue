<script lang="ts" setup>
import { watch, shallowRef, ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router'
import { fetchDeck, deleteDeck, fetchCards, syncDeck, updateDeck } from '@/arkham/api';
import { imgsrc, localizeArkhamDBBaseUrl } from '@/arkham/helpers';
import * as Arkham from '@/arkham/types/CardDef';
import type {Deck, ArkhamDbDecklist} from '@/arkham/types/Deck';
import * as DeckHelpers from '@/arkham/types/Deck';
import Prompt from '@/components/Prompt.vue'
import CardListView from '@/arkham/components/CardListView.vue'
import CardImageView from '@/arkham/components/CardImageView.vue'
import { useToast } from "vue-toastification";
import { useDbCardStore, ArkhamDBCard } from '@/stores/dbCards'
import { displayTabooId } from '@/arkham/taboo'

export interface Props {
  deckId: string
}

const props = defineProps<Props>()
const router = useRouter()
const toast = useToast()
const allCards = shallowRef<Arkham.CardDef[]>([])
const ready = ref(false)
const deleting = ref(false)
const deck = shallowRef<Deck | null>(null)
const deckRef = ref(null)
const store = useDbCardStore()

// Editing state
const editing = ref(false)
const editedSlots = ref<Record<string, number>>({})
const newCardCode = ref('')
const newCardCount = ref(1)
const searchQuery = ref('')
const showSearchResults = ref(false)
const searchInputRef = ref<HTMLInputElement | null>(null)

// Search cards by name or code
const searchResults = computed(() => {
  if (!searchQuery.value.trim()) return []
  const query = searchQuery.value.toLowerCase().trim()
  return allCards.value.filter(card => {
    const nameMatch = card.name.title.toLowerCase().includes(query)
    const codeMatch = card.art.toLowerCase().includes(query)
    return nameMatch || codeMatch
  }).slice(0, 10) // Limit to 10 results
})

// Get card name by code (for displaying in the list)
function getCardName(cardCode: string): string {
  if (cardCode === 'c01000') return 'Random Basic Weakness'
  const art = cardCode.startsWith('c') ? cardCode.slice(1) : cardCode
  const card = allCards.value.find(c => c.art === art)
  return card ? card.name.title : cardCode
}

// Select card from search results
function selectCard(card: Arkham.CardDef) {
  newCardCode.value = card.art // Store without 'c' prefix
  searchQuery.value = `${card.name.title} (${card.art})`
  showSearchResults.value = false
}

// Handle search input blur
function handleSearchBlur() {
  // Delay to allow click on results
  setTimeout(() => {
    showSearchResults.value = false
  }, 200)
}

// Handle search input focus
function handleSearchFocus() {
  if (searchQuery.value.trim()) {
    showSearchResults.value = true
  }
}

onMounted(() => {
  if (deckRef.value !== null) {
    const el = deckRef.value
    const observer = new IntersectionObserver(
      ([e]) => e.target.classList.toggle("is-pinned", e.intersectionRatio < 1),
      { threshold: [1] }
    );

    observer.observe(el);
  }
})

const enum View {
  Image = "IMAGE",
  List = "LIST",
}

fetchCards(true).then((response) => {
  allCards.value = response.sort((a, b) => {
    if (a.art < b.art) return -1
    if (a.art > b.art) return 1
    return 0
  })

  fetchDeck(props.deckId).then((deckData) => {
    deck.value = deckData
    ready.value = true
  })
})

const view = ref(View.List)

const cards = computed(() => {
  if (deck.value === undefined || deck.value === null) {
    return []
  }

  const slots = editing.value ? editedSlots.value : deck.value.list.slots

  return Object.entries(slots).flatMap(([key, value]) => {
    if (key === "c01000") {
      return Array(value).fill({ cardCode: key, classSymbols: [], cardType: "Treachery", art: "01000", level: 0, name: { title: "Random Basic Weakness", subtitle: null }, cardTraits: [], skills: [], cost: null })
    }

    const result: Arkham.CardDef | undefined = allCards.value.find((c) => `c${c.art}` === key)
    const language = localStorage.getItem('language') || 'en'
    if (language === 'en') return Array(value).fill(result)

    if (!result) return
    const match: ArkhamDBCard | null = store.getDbCard(result.art)
    if (!match) return Array(value).fill(result)

    // Name
    result.name.title = match.name
    if (match.subname) result.name.subtitle = match.subname

    // Class
    if (match.faction_name && result.classSymbols.length > 0) result.classSymbols[0] = match.faction_name
    if (match.faction2_name && result.classSymbols.length > 1) {
      result.classSymbols[1] = match.faction2_name
      if (match.faction3_name && result.classSymbols.length > 2) result.classSymbols[2] = match.faction3_name
    }

    // Type
    result.cardType = match.type_name

    // Traits
    if (match.traits) result.cardTraits = match.traits.split('.').filter(item => item != "" && item != " ")

    return Array(value).fill(result)
  })
})

async function deleteDeckEvent() {
  if (deck.value) {
    deleteDeck(deck.value.id).then(() => {
      router.push({ name: 'Decks' })
    })
  }
}

async function sync() {
  if (deck.value) {
    syncDeck(deck.value.id).then((newData) => {
      toast.success("Deck synced successfully", { timeout: 3000 })
      deck.value = newData
    })
  }
}

function startEditing() {
  if (deck.value) {
    editedSlots.value = { ...deck.value.list.slots }
    editing.value = true
  }
}

function cancelEditing() {
  editing.value = false
  editedSlots.value = {}
  newCardCode.value = ''
  newCardCount.value = 1
}

async function saveDeck() {
  if (!deck.value) return

  // Validate all card codes exist
  const invalidCards = Object.keys(editedSlots.value).filter(code => {
    if (code === 'c01000') return false // Random Basic Weakness is always valid
    const cardCode = code.replace(/^c/, '')
    return !allCards.value.some(c => c.art === cardCode)
  })

  if (invalidCards.length > 0) {
    toast.error(`Invalid card codes: ${invalidCards.join(', ')}`, { timeout: 5000 })
    return
  }

  // Remove cards with count 0 or less
  const cleanedSlots: Record<string, number> = {}
  for (const [code, count] of Object.entries(editedSlots.value)) {
    if (count > 0) {
      cleanedSlots[code] = count
    }
  }

  const decklist: ArkhamDbDecklist = {
    id: deck.value.id,
    url: deck.value.url,
    name: deck.value.name,
    investigator_code: deck.value.list.investigator_code,
    investigator_name: deck.value.list.investigator_name || deck.value.name,
    slots: cleanedSlots,
    taboo_id: deck.value.list.taboo_id,
    sideSlots: {},
  }

  try {
    const updatedDeck = await updateDeck(deck.value.id, decklist)
    deck.value = updatedDeck
    editing.value = false
    editedSlots.value = {}
    toast.success("Deck updated successfully", { timeout: 3000 })
  } catch (err) {
    toast.error("Failed to update deck", { timeout: 3000 })
    console.error(err)
  }
}

function addCard() {
  if (!newCardCode.value.trim()) return
  
  let cardCode = newCardCode.value.trim()
  // Ensure card code starts with 'c'
  if (!cardCode.startsWith('c')) {
    cardCode = 'c' + cardCode
  }
  
  const count = Math.max(1, Math.min(newCardCount.value, 99))
  
  if (editedSlots.value[cardCode]) {
    editedSlots.value[cardCode] += count
  } else {
    editedSlots.value[cardCode] = count
  }
  
  // Reset search
  newCardCode.value = ''
  searchQuery.value = ''
  newCardCount.value = 1
  showSearchResults.value = false
}

function removeCard(cardCode: string) {
  if (editedSlots.value[cardCode]) {
    editedSlots.value[cardCode]--
    if (editedSlots.value[cardCode] <= 0) {
      delete editedSlots.value[cardCode]
    }
  }
}

function getCardCount(cardCode: string): number {
  return editedSlots.value[cardCode] || 0
}

const deckUrlToPage = (url: string): string => {
  return url.replace("https://arkhamdb.com", localizeArkhamDBBaseUrl()).replace("/api/public/decklist", "/decklist/view").replace("/api/public/deck", "/deck/view")
}

const deckInvestigator = computed(() => {
  if (deck.value) {
    if (deck.value.list.meta) {
      try {
        const result = JSON.parse(deck.value.list.meta)
        if (result && result.alternate_front) {
          return result.alternate_front
        }
      } catch (e) { console.log("No parse") }
    }
    return deck.value.list.investigator_code.replace('c', '')
  }

  return null
})

const deckClass = computed(() => {
  if (deck.value) return DeckHelpers.deckClass(deck.value)
  return {}
})

const tabooList = computed(() => {
  return deck.value?.list.taboo_id ? displayTabooId(deck.value.list.taboo_id) : null
})

watch(deckRef, (el) => {
  if (el !== null) {
    const observer = new IntersectionObserver(
      ([e]) => e.target.classList.toggle("is-pinned", e.intersectionRatio < 1),
      { threshold: [1] }
    );

    observer.observe(el);
  }
})

</script>

<template>
  <div class="container">
    <div class="results">
      <header class="deck" v-show="deck" ref="deckRef" :class="deckClass">
        <template v-if="deck">
          <img v-if="deckInvestigator" class="portrait--decklist" :src="imgsrc(`cards/${deckInvestigator}.avif`)" />
          <div class="deck--details">
            <div class="deck-main">
              <h1 class="deck-title">{{deck.name}}</h1>
              <span v-if="tabooList" class="taboo-badge"><font-awesome-icon icon="book" /> Taboo: {{ tabooList }}</span>
            </div>
          </div>
          <div class="deck--actions">
            <div class="deck--view-options">
              <button @click.prevent="view = View.List" :class="{ pressed: view == View.List }">
                <font-awesome-icon icon="list" />
              </button>
              <button @click.prevent="view = View.Image" :class="{ pressed: view == View.Image }">
                <font-awesome-icon icon="image" />
              </button>
            </div>
            <div class="deck-actions">
              <a v-if="!editing" class="action-btn" href="#" title="Edit deck" @click.prevent="startEditing"><font-awesome-icon icon="pen" /></a>
              <a v-if="deck.url" class="action-btn" :href="deckUrlToPage(deck.url)" target="_blank" rel="noreferrer noopener" title="View on ArkhamDB"><font-awesome-icon icon="external-link" /></a>
              <a v-if="deck.url && !editing" class="action-btn" href="#" title="Sync deck" @click.prevent="sync"><font-awesome-icon icon="refresh" /></a>
              <a v-if="!editing" class="action-btn action-btn--delete" href="#" title="Delete deck" @click.prevent="deleting = true"><font-awesome-icon icon="trash" /></a>
              <template v-if="editing">
                <a class="action-btn action-btn--save" href="#" title="Save changes" @click.prevent="saveDeck"><font-awesome-icon icon="check" /></a>
                <a class="action-btn action-btn--cancel" href="#" title="Cancel editing" @click.prevent="cancelEditing"><font-awesome-icon icon="times" /></a>
              </template>
            </div>
          </div>
        </template>
      </header>
      
      <!-- Editor Panel -->
      <div v-if="editing" class="editor-panel">
        <div class="editor-controls">
          <div class="add-card-section">
            <h3>Add Card</h3>
            <div class="add-card-inputs">
              <div class="search-container">
                <input 
                  ref="searchInputRef"
                  v-model="searchQuery" 
                  placeholder="Search card name or code..." 
                  @input="showSearchResults = searchQuery.trim().length > 0"
                  @focus="handleSearchFocus"
                  @blur="handleSearchBlur"
                  @keyup.enter="addCard"
                />
                <!-- Search Results Dropdown -->
                <div v-if="showSearchResults && searchResults.length > 0" class="search-results">
                  <div 
                    v-for="card in searchResults" 
                    :key="card.art"
                    class="search-result-item"
                    @click="selectCard(card)"
                  >
                    <span class="result-name">{{ card.name.title }}</span>
                    <span class="result-code">({{ card.art }})</span>
                  </div>
                </div>
                <div v-if="showSearchResults && searchQuery.trim() && searchResults.length === 0" class="search-results no-results">
                  No cards found
                </div>
              </div>
              <input 
                v-model.number="newCardCount" 
                type="number" 
                min="1" 
                max="99" 
                class="count-input"
              />
              <button @click="addCard" class="add-btn">
                <font-awesome-icon icon="plus" /> Add
              </button>
            </div>
          </div>
          <div class="deck-stats">
            <span>Cards in deck: {{ Object.values(editedSlots).reduce((a, b) => a + b, 0) }}</span>
          </div>
        </div>
        
        <!-- Editable Card List -->
        <div class="editable-card-list">
          <div v-for="(count, cardCode) in editedSlots" :key="cardCode" class="editable-card-item">
            <span class="card-name-code">
              <span class="card-name">{{ getCardName(cardCode) }}</span>
              <span class="card-code">({{ cardCode.startsWith('c') ? cardCode.slice(1) : cardCode }})</span>
            </span>
            <span class="card-count">
              <button @click="removeCard(cardCode)" class="count-btn">
                <font-awesome-icon icon="minus" />
              </button>
              <span class="count-display">{{ count }}</span>
              <button @click="editedSlots[cardCode]++" class="count-btn">
                <font-awesome-icon icon="plus" />
              </button>
            </span>
          </div>
        </div>
      </div>
      
      <CardImageView v-if="view == View.Image && !editing" :cards="cards" />
      <CardListView v-if="view == View.List && !editing" :cards="cards" />
    </div>
    <Prompt
      v-if="deleting"
      prompt="Are you sure you want to delete this deck?"
      :yes="deleteDeckEvent"
      :no="() => deleting = false"
    />
  </div>
</template>

<style scoped>
/* ── Layout ─────────────────────────────────────────────── */

.container {
  display: flex;
  height: calc(100vh - var(--nav-height));
  max-width: unset;
  margin: 0;
  overflow: hidden;
  @media (max-width: 768px) {
    height: auto;
    overflow-x: hidden;
    overflow-y: visible;
    flex-direction: column;
  }
}

.results {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  @media (max-width: 768px) {
    overflow: visible;
  }
}

/* ── Deck header ─────────────────────────────────────────── */

.deck {
  --deck-pad: 20px;
  display: flex;
  flex-wrap: wrap;
  column-gap: 16px;
  row-gap: 0;
  padding: var(--deck-pad) 0 0;
  color: #f0f0f0;
  background: var(--box-background);
  border-left: 4px solid transparent;
  box-shadow: 1px 1px 6px rgba(0, 0, 0, 0.45);
  position: sticky;
  position: -webkit-sticky;
  top: -1px;
  flex-shrink: 0;
  align-items: flex-start;
  @media (max-width: 768px) {
    --deck-pad: 12px;
    position: static;
    padding: 10px 0 0;
  }

  &.guardian { border-left-color: var(--guardian-dark); }
  &.seeker   { border-left-color: var(--seeker-dark); }
  &.rogue    { border-left-color: var(--rogue-dark); }
  &.mystic   { border-left-color: var(--mystic-dark); }
  &.survivor { border-left-color: var(--survivor-dark); }
  &.neutral  { border-left-color: var(--neutral-dark); }
}

.portrait--decklist {
  width: 200px;
  flex-shrink: 0;
  align-self: flex-start;
  border-radius: 10px;
  box-shadow: 1px 1px 6px rgba(0, 0, 0, 0.45);
  margin-left: var(--deck-pad);
  @media (max-width: 768px) {
    width: 72px;
    border-radius: 6px;
  }
}

.deck--details {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
  margin-right: var(--deck-pad);
  margin-bottom: var(--deck-pad);
}

.deck-main {
  display: flex;
  flex-direction: column;
  gap: 8px;
  flex: 1;
  @media (max-width: 768px) {
    min-width: 0;
    gap: 4px;
  }
}

.deck-title {
  font-weight: 800;
  font-size: 2em;
  margin: 0;
  padding: 0;
  @media (max-width: 768px) {
    font-size: 1.1em;
  }
}

.taboo-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  width: fit-content;
  padding: 1px 7px;
  line-height: 1.6;
  font-size: 0.75em;
  font-weight: 600;
  color: #c8a96e;
  background: rgba(200, 169, 110, 0.12);
  border: 1px solid rgba(200, 169, 110, 0.25);
  border-radius: 4px;
  letter-spacing: 0.02em;
}

.deck--actions {
  display: flex;
  align-items: center;
  gap: 16px;
  flex-basis: 100%;
  padding: 8px var(--deck-pad);
  background: rgba(0, 0, 0, 0.2);
  border-top: 1px solid rgba(255, 255, 255, 0.08);
}

.deck--view-options {
  display: flex;
  gap: 2px;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 6px;
  padding: 2px;
  width: fit-content;

  button {
    background: transparent;
    border: none;
    border-radius: 4px;
    padding: 5px 9px;
    color: #777;
    cursor: pointer;
    transition: background 0.12s, color 0.12s;

    &:hover { color: #ccc; }
    &.pressed { background: rgba(255,255,255,0.12); color: #eee; }
  }
}

.deck-actions {
  display: flex;
  align-items: center;
  gap: 14px;
}

.action-btn {
  color: #8a93a8;
  font-size: 0.9em;
  text-decoration: none;
  transition: color 0.15s;

  &:hover { color: #fff; }
  &.action-btn--delete:hover { color: #ff6666; }
  &.action-btn--save:hover { color: #66ff66; }
  &.action-btn--cancel:hover { color: #ffaa66; }
}

/* ── Editor Panel ───────────────────────────────────────── */

.editor-panel {
  background: var(--box-background);
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  padding: 16px 20px;
  overflow-y: auto;
}

.editor-controls {
  display: flex;
  flex-wrap: wrap;
  gap: 20px;
  margin-bottom: 16px;
  align-items: flex-start;
}

.add-card-section {
  flex: 1;
  min-width: 300px;
  
  h3 {
    margin: 0 0 8px 0;
    font-size: 0.9em;
    color: #aaa;
  }
}

.add-card-inputs {
  display: flex;
  gap: 8px;
  align-items: flex-start;
  
  input {
    background: rgba(0, 0, 0, 0.3);
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 4px;
    padding: 8px 12px;
    color: #f0f0f0;
    font-size: 0.9em;
    
    &:focus {
      outline: none;
      border-color: rgba(255, 255, 255, 0.3);
    }
    
    &::placeholder {
      color: #666;
    }
  }
  
  .count-input {
    width: 60px;
    text-align: center;
  }
}

.search-container {
  position: relative;
  flex: 1;
  min-width: 250px;
}

.search-results {
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  max-height: 300px;
  overflow-y: auto;
  background: #2a2a3a;
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 4px;
  margin-top: 4px;
  z-index: 100;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
}

.search-result-item {
  padding: 10px 12px;
  cursor: pointer;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
  display: flex;
  align-items: center;
  gap: 8px;
  transition: background 0.15s;
  
  &:hover {
    background: rgba(255, 255, 255, 0.1);
  }
  
  &:last-child {
    border-bottom: none;
  }
  
  .result-name {
    color: #f0f0f0;
    font-weight: 500;
  }
  
  .result-code {
    color: #888;
    font-size: 0.85em;
    font-family: monospace;
  }
}

.no-results {
  padding: 12px;
  color: #888;
  text-align: center;
  font-size: 0.9em;
}

.add-btn {
  background: rgba(100, 180, 100, 0.2);
  border: 1px solid rgba(100, 180, 100, 0.4);
  border-radius: 4px;
  padding: 8px 16px;
  color: #8f8;
  cursor: pointer;
  transition: all 0.15s;
  
  &:hover {
    background: rgba(100, 180, 100, 0.3);
    border-color: rgba(100, 180, 100, 0.6);
  }
}

.deck-stats {
  color: #888;
  font-size: 0.9em;
  padding: 8px 0;
}

.editable-card-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.editable-card-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 12px;
  background: rgba(0, 0, 0, 0.2);
  border-radius: 4px;
  
  .card-name-code {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: 1;
    min-width: 0;
  }
  
  .card-name {
    color: #f0f0f0;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  
  .card-code {
    font-family: monospace;
    color: #888;
    font-size: 0.85em;
    flex-shrink: 0;
  }
  
  .card-count {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
  }
  
  .count-display {
    min-width: 24px;
    text-align: center;
    color: #f0f0f0;
    font-weight: 600;
  }
  
  .count-btn {
    background: rgba(255, 255, 255, 0.1);
    border: none;
    border-radius: 3px;
    padding: 4px 8px;
    color: #aaa;
    cursor: pointer;
    transition: all 0.15s;
    
    &:hover {
      background: rgba(255, 255, 255, 0.2);
      color: #fff;
    }
  }
}
</style>

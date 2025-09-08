<script setup lang="ts">
import { ref, reactive, onMounted, onUnmounted, computed } from 'vue';
import { search, type SearchParams } from '@/api';
import type { SearchResponse, MergedResults } from '@/types';
import SearchForm from '@/components/SearchForm.vue';
import ResultTabs from '@/components/ResultTabs.vue';
import SearchStats from '@/components/SearchStats.vue';
import ApiStatus from '@/components/ApiStatus.vue';
import ApiDocs from '@/components/ApiDocs.vue';

// 搜索状态
const loading = ref(false);
const searchResults = reactive<{
  total: number;
  mergedResults: MergedResults;
}>({
  total: 0,
  mergedResults: {}
});

// 搜索时间
const searchTime = ref<number | undefined>(undefined);

// 后台更新状态
const isUpdating = ref(false);
const updateCount = ref(0);
const updateTimer = ref<number | null>(null);
const secondSearchTimeout = ref<number | null>(null);
const thirdSearchTimeout = ref<number | null>(null);
const lastSearchParams = ref<SearchParams | null>(null);

// 是否已经执行过搜索
const hasSearched = ref(false);
// 是否正在进行后台搜索（包括初始搜索和后续更新）
const isActivelySearching = ref(false);

// 当前页面状态
const currentPage = ref<'search' | 'status' | 'docs'>('search');

// --- [新增] 页脚年份和运行天数 ---
const copyrightYear = ref(new Date().getFullYear());
const siteStartDate = '6/4/2025'; // 从您的 config.json 获取
const runDays = ref('');

const calculateRunDays = () => {
  if (siteStartDate) {
    const startSite = new Date(siteStartDate);
    const now = new Date();
    const diff = now.getTime() - startSite.getTime();
    const diffDay = Math.floor(diff / (1000 * 60 * 60 * 24));
    runDays.value = `本站已运行${diffDay}天 • `;
  }
};

// 页面切换
const switchToStatus = () => {
  currentPage.value = 'status';
};

const switchToDocs = () => {
  currentPage.value = 'docs';
};

// 处理搜索
const handleSearch = async (params: SearchParams) => {
  // 停止之前的更新
  stopUpdate();
  
  hasSearched.value = true;
  isActivelySearching.value = true;
  loading.value = true;
  
  searchResults.total = 0;
  searchResults.mergedResults = {};
  searchTime.value = undefined;
  
  lastSearchParams.value = { ...params };
  
  const startTime = Date.now();
  
  try {
    const tgParams: SearchParams = { ...params, src: 'tg' };
    const allParams: SearchParams = { ...params, src: 'all' };
    
    search(tgParams)
      .then(tgResponse => {
        if (tgResponse && tgResponse.total !== undefined) {
          updateSearchResults(tgResponse);
          searchTime.value = Date.now() - startTime;
          loading.value = false;
          
          search(allParams)
            .then(allResponse => {
              const firstAllSearchCompleteTime = Date.now();
              if (allResponse && allResponse.total >= searchResults.total) {
                updateSearchResults(allResponse);
              }
              startSecondAllSearch(firstAllSearchCompleteTime);
            })
            .catch(error => {
              console.error('第一次ALL搜索出错:', error);
              startSecondAllSearch(Date.now());
            });
        } else {
          console.error('TG搜索结果格式不正确:', tgResponse);
          loading.value = false;
          
          search(allParams)
            .then(allResponse => {
              if (allResponse && allResponse.total !== undefined) {
                updateSearchResults(allResponse);
                const firstAllSearchCompleteTime = Date.now();
                startSecondAllSearch(firstAllSearchCompleteTime);
              }
            })
            .catch(error => {
              console.error('第一次ALL搜索出错:', error);
              isActivelySearching.value = false;
            });
        }
      })
      .catch(error => {
        console.error('TG搜索出错:', error);
        loading.value = false;
        
        search(allParams)
          .then(allResponse => {
            if (allResponse && allResponse.total !== undefined) {
              updateSearchResults(allResponse);
              const firstAllSearchCompleteTime = Date.now();
              startSecondAllSearch(firstAllSearchCompleteTime);
            }
          })
          .catch(error => {
            console.error('第一次ALL搜索出错:', error);
            isActivelySearching.value = false;
          });
      });
    
    setTimeout(() => {
      if (loading.value) {
        loading.value = false;
      }
    }, 5000);
    
  } catch (error) {
    console.error('搜索初始化出错:', error);
    loading.value = false;
    isActivelySearching.value = false;
  }
};

// 更新搜索结果
const updateSearchResults = (response: SearchResponse) => {
  if (!response) return;
  searchResults.total = response.total || 0;
  searchResults.mergedResults = response.merged_by_type ? { ...response.merged_by_type } : {};
};

// 开始第二次ALL源搜索
const startSecondAllSearch = (firstAllSearchCompleteTime: number) => {
  if (!lastSearchParams.value) return;
  
  isUpdating.value = true;
  isActivelySearching.value = true;
  updateCount.value = 1;
  
  const allParams: SearchParams = { ...lastSearchParams.value, src: 'all' };
  const delay = Math.max(0, 2000 - (Date.now() - firstAllSearchCompleteTime));
  
  secondSearchTimeout.value = window.setTimeout(async () => {
    if (!lastSearchParams.value) { stopUpdate(); return; }
    try {
      const response = await search(allParams);
      if (response && response.total >= searchResults.total) {
        updateSearchResults(response);
      }
      startThirdAllSearch(Date.now());
    } catch (error) {
      console.error('第二次ALL搜索出错:', error);
      stopUpdate();
    }
  }, delay);
};

// 开始第三次ALL源搜索
const startThirdAllSearch = (secondAllSearchCompleteTime: number) => {
  if (!lastSearchParams.value) return;
  
  updateCount.value = 2;
  const allParams: SearchParams = { ...lastSearchParams.value, src: 'all' };
  const delay = Math.max(0, 3000 - (Date.now() - secondAllSearchCompleteTime));
  
  thirdSearchTimeout.value = window.setTimeout(async () => {
    if (!lastSearchParams.value) { stopUpdate(); return; }
    try {
      const response = await search(allParams);
      if (response && response.total >= searchResults.total) {
        updateSearchResults(response);
      }
    } catch (error) {
      console.error('第三次ALL搜索出错:', error);
    } finally {
      stopUpdate();
    }
  }, delay);
};

// 停止后台更新
const stopUpdate = () => {
  if (updateTimer.value) clearInterval(updateTimer.value);
  if (secondSearchTimeout.value) clearTimeout(secondSearchTimeout.value);
  if (thirdSearchTimeout.value) clearTimeout(thirdSearchTimeout.value);
  updateTimer.value = secondSearchTimeout.value = thirdSearchTimeout.value = null;
  isUpdating.value = false;
  isActivelySearching.value = false;
};

// 重置到初始页面
const resetToInitial = () => {
  stopUpdate();
  currentPage.value = 'search';
  hasSearched.value = false;
  isActivelySearching.value = false;
  loading.value = false;
  searchResults.total = 0;
  searchResults.mergedResults = {};
  searchTime.value = undefined;
  isUpdating.value = false;
  updateCount.value = 0;
};

// 组件挂载时计算运行天数
onMounted(() => {
  calculateRunDays();
});

onUnmounted(() => {
  stopUpdate();
});
</script>

<template>
  <div class="min-h-screen bg-background text-foreground transition-colors duration-300 flex flex-col">
    <div class="bg-decorative"></div>
    
    <header id="header" class="page-header">
      <nav class="header-nav-menu">
        <a href="https://www.futuremedia.work/">首页</a>
        <a href="https://www.futuremedia.work/tag.html#身心健康">身心健康</a>
        <a href="https://www.futuremedia.work/tag.html#投资理财">投资理财</a>
        <a href="https://www.futuremedia.work/tag.html#学习成长">学习成长</a>
        <a href="https://www.futuremedia.work/tag.html#潮流工具">潮流工具</a>
        <a href="https://www.futuremedia.work/tag.html#其他话题">其他话题</a>
        <a href="http://pansou.futuremedia.work">网盘搜索</a>
        <a href="https://www.futuremedia.work/about.html">关于本站</a>
        <a href="#" @click.prevent title="将本站加入收藏夹">收藏本站</a>
      </nav>

      <div class="header-main-content">
        <div class="flex items-center gap-3 cursor-pointer" @click="resetToInitial">
          <div class="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
            <svg class="w-5 h-5 text-primary-foreground" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
            </svg>
          </div>
          <div>
            <h1 class="text-xl font-bold text-white shadow-text">网盘搜索-未来传媒-专注中年人</h1>
          </div>
        </div>
      </div>
    </header>
    
    <main class="container mx-auto px-4 py-8 flex-1">
      <div v-if="currentPage === 'search'" class="search-page">
        <div class="mb-6">
          <SearchForm @search="handleSearch" />
        </div>
        <div v-if="hasSearched || loading" class="mb-6">
          <SearchStats 
            :total="searchResults.total" 
            :mergedResults="searchResults.mergedResults" 
            :loading="loading"
            :searchTime="searchTime"
            :isUpdating="isUpdating"
            :updateCount="updateCount"
          />
        </div>
        <div v-if="loading" class="card p-6">
          <div class="space-y-3">
            <div class="h-4 bg-muted rounded animate-pulse" v-for="n in 5" :key="n"></div>
          </div>
        </div>
        <div v-else>
          <ResultTabs 
            :mergedResults="searchResults.mergedResults" 
            :loading="loading"
            :hasSearched="hasSearched"
            :isActivelySearching="isActivelySearching"
          />
        </div>
      </div>
      <div v-else-if="currentPage === 'status'" class="status-page">
        <ApiStatus />
      </div>
      <div v-else-if="currentPage === 'docs'" class="docs-page">
        <ApiDocs />
      </div>
    </main>
    
    <footer class="site-footer">
      <div id="footer1">
        Copyright all reserved © {{ copyrightYear }}-future 
        <a href="https://www.futuremedia.work">未来传媒</a><br>
        <a href="https://www.futuremedia.work/about.html">关于本站</a> |
        <a href="https://www.futuremedia.work/terms-of-service.html">服务条款</a> |  
        <a href="https://www.futuremedia.work/privacy-policy.html">隐私政策</a> |
        <a href="https://www.futuremedia.work/disclaimer.html">免责声明</a> 
      </div>
      <div id="footer2">
        <span>{{ runDays }}</span>
        <span>本站由<a href="mailto:futuremedia2090@gmail.com" target="_blank">疯子</a>维护</span>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.bg-decorative {
  position: fixed;
  inset: 0;
  z-index: -10;
  background-image: radial-gradient(circle at 1px 1px, hsl(var(--muted-foreground)) 1px, transparent 0);
  background-size: 20px 20px;
  opacity: 0.1;
}

/* [ADDED] 新增页眉样式 */
.page-header {
    position: relative;
    background-image: url('/images/header-bg.png'); /* 确保这个路径在你的 public 文件夹下是可访问的 */
    background-size: cover;
    background-position: center center;
    padding: 1.5rem 1.5rem;
    border-radius: 8px;
    margin: 20px auto 2rem auto;
    max-width: 900px; /* 匹配主内容宽度 */
    width: calc(100% - 30px); /* 匹配主内容宽度 */
    color: white;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    gap: 1.2rem;
    border-bottom: 1px solid rgba(255, 255, 255, 0.2);
}

.page-header::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: rgba(0, 0, 0, 0.5);
    z-index: 1;
}

.page-header > * {
    position: relative;
    z-index: 2;
}

.page-header a {
    color: white !important;
    text-decoration: none;
}

.header-main-content {
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
}

.header-nav-menu {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 8px 12px;
}

.header-nav-menu a {
    padding: 8px 12px;
    font-size: 14px;
    font-weight: bold;
    border-radius: 5px;
    transition: background-color 0.3s ease;
}

.header-nav-menu a:hover {
    background-color: rgba(255, 255, 255, 0.15);
}
.shadow-text {
    text-shadow: 1px 1px 3px rgba(0,0,0,0.5);
}

/* 页面切换动画 */
.search-page, .status-page {
  animation: fadeIn 0.3s ease-in-out;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

/* [ADDED] 新增页脚样式 */
.site-footer {
    padding: 20px 0;
    margin-top: 64px;
    text-align: center;
    font-size: small;
    color: black !important;
}
.site-footer a {
    color: black !important;
}

/* 响应式调整 */
@media (max-width: 768px) {
  .container {
    padding-left: 1rem;
    padding-right: 1rem;
  }
  .page-header {
    width: calc(100% - 2rem); /* 调整移动端宽度 */
    margin-left: 1rem;
    margin-right: 1rem;
  }
}
</style>

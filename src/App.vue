<script setup lang="ts">
import { ref, reactive, onMounted, onUnmounted } from 'vue';
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
  
  // 标记已执行搜索和正在搜索
  hasSearched.value = true;
  isActivelySearching.value = true;
  
  // 重置状态
  loading.value = true;
  
  // 清空之前的搜索结果
  searchResults.total = 0;
  searchResults.mergedResults = {};
  searchTime.value = undefined;
  
  // 保存搜索参数
  lastSearchParams.value = { ...params };
  
  const startTime = Date.now();
  
  try {
    // 创建TG源搜索参数
    const tgParams: SearchParams = {
      ...params,
      src: 'tg'
    };
    
    // 创建ALL源搜索参数
    const allParams: SearchParams = {
      ...params,
      src: 'all'
    };
    
    // 先发起TG源搜索请求
    search(tgParams)
      .then(tgResponse => {
        
        if (tgResponse && tgResponse.total !== undefined) {
          // 使用TG的搜索结果进行显示
          updateSearchResults(tgResponse);
          searchTime.value = Date.now() - startTime;
          // TG搜索完成后，关闭加载状态
          loading.value = false;
          
          // TG搜索完成后，再发起第一次ALL源搜索
          search(allParams)
            .then(allResponse => {
              
              // 记录第一次ALL搜索完成时间
              const firstAllSearchCompleteTime = Date.now();
              
              // 如果ALL源结果比当前结果更多，则更新显示
              if (allResponse && allResponse.total >= searchResults.total) {
                updateSearchResults(allResponse);
              }
              
              // 开始第二次ALL源搜索
              startSecondAllSearch(firstAllSearchCompleteTime);
            })
            .catch(error => {
              console.error('第一次ALL搜索出错:', error);
              
              // 即使第一次ALL搜索失败，也继续进行第二次搜索
              startSecondAllSearch(Date.now());
            });
        } else {
          console.error('TG搜索结果格式不正确:', tgResponse);
          loading.value = false;
          
          // 即使TG搜索失败，也尝试ALL源搜索
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
        
        // TG搜索出错时，尝试ALL源搜索
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
    
    // 设置一个超时，确保即使搜索很慢，UI也不会一直处于加载状态
    setTimeout(() => {
      if (loading.value) {
        loading.value = false;
      }
    }, 5000); // 5秒后如果还在加载，则关闭加载状态
    
  } catch (error) {
    console.error('搜索初始化出错:', error);
    loading.value = false;
    isActivelySearching.value = false;
  }
};

// 搜索完成处理
const handleSearchComplete = () => {
  // 只处理UI相关的状态，不影响搜索流程
};

// 更新搜索结果
const updateSearchResults = (response: SearchResponse) => {
  if (!response) return;
  
  searchResults.total = response.total || 0;
  
  if (response.merged_by_type) {
    searchResults.mergedResults = { ...response.merged_by_type };
  } else {
    console.warn('搜索结果中没有merged_by_type字段');
    searchResults.mergedResults = {};
  }
};

// 开始第二次ALL源搜索
const startSecondAllSearch = (firstAllSearchCompleteTime: number) => {
  if (!lastSearchParams.value) return;
  
  isUpdating.value = true;
  isActivelySearching.value = true;
  updateCount.value = 1;
  
  // 创建ALL源搜索参数
  const allParams: SearchParams = {
    ...lastSearchParams.value,
    src: 'all'
  };
  
  // 计算需要等待的时间，确保与第一次ALL搜索至少间隔2秒
  const currentTime = Date.now();
  const timeElapsedSinceFirstAllSearch = currentTime - firstAllSearchCompleteTime;
  const delayForSecondSearch = Math.max(0, 2000 - timeElapsedSinceFirstAllSearch);
  
  // 执行第二次ALL搜索
  const executeSecondAllSearch = async () => {
    if (!lastSearchParams.value) {
      stopUpdate();
      return;
    }
    
    try {
      const secondAllSearchStartTime = Date.now();
      const response = await search(allParams);
      
      // 更新结果
      if (response && response.total >= searchResults.total) {
        updateSearchResults(response);
      }
      
      // 记录第二次ALL搜索完成时间
      const secondAllSearchCompleteTime = Date.now();
      
      // 开始第三次ALL源搜索
      startThirdAllSearch(secondAllSearchCompleteTime);
    } catch (error) {
      console.error('第二次ALL搜索出错:', error);
      stopUpdate();
    }
  };
  
  // 设置定时器，在适当的时间执行第二次ALL搜索
  secondSearchTimeout.value = window.setTimeout(executeSecondAllSearch, delayForSecondSearch);
};

// 开始第三次ALL源搜索
const startThirdAllSearch = (secondAllSearchCompleteTime: number) => {
  if (!lastSearchParams.value) return;
  
  updateCount.value = 2;
  
  // 创建ALL源搜索参数
  const allParams: SearchParams = {
    ...lastSearchParams.value,
    src: 'all'
  };
  
  // 计算需要等待的时间，确保与第二次ALL搜索至少间隔3秒
  const currentTime = Date.now();
  const timeElapsedSinceSecondAllSearch = currentTime - secondAllSearchCompleteTime;
  const delayForThirdSearch = Math.max(0, 3000 - timeElapsedSinceSecondAllSearch);
  
  // 执行第三次ALL搜索
  const executeThirdAllSearch = async () => {
    if (!lastSearchParams.value) {
      stopUpdate();
      return;
    }
    
    try {
      const response = await search(allParams);
      
      // 更新结果
      if (response && response.total >= searchResults.total) {
        updateSearchResults(response);
      }
    } catch (error) {
      console.error('第三次ALL搜索出错:', error);
    } finally {
      // 完成所有搜索，停止更新
      stopUpdate();
    }
  };
  
  // 设置定时器，在适当的时间执行第三次ALL搜索
  thirdSearchTimeout.value = window.setTimeout(executeThirdAllSearch, delayForThirdSearch);
};

// 停止后台更新
const stopUpdate = () => {
  // 清除所有定时器
  if (updateTimer.value) {
    clearInterval(updateTimer.value);
    updateTimer.value = null;
  }
  
  if (secondSearchTimeout.value) {
    clearTimeout(secondSearchTimeout.value);
    secondSearchTimeout.value = null;
  }
  
  if (thirdSearchTimeout.value) {
    clearTimeout(thirdSearchTimeout.value);
    thirdSearchTimeout.value = null;
  }
  
  // 标记搜索已结束
  isUpdating.value = false;
  isActivelySearching.value = false;
};

// 重置到初始页面
const resetToInitial = () => {
  // 停止之前的更新
  stopUpdate();
  
  // 切换到搜索页面
  currentPage.value = 'search';
  
  // 重置所有状态
  hasSearched.value = false;
  isActivelySearching.value = false;
  loading.value = false;
  searchResults.total = 0;
  searchResults.mergedResults = {};
  searchTime.value = undefined;
  isUpdating.value = false;
  updateCount.value = 0;
};

// 组件卸载时清除定时器
onMounted(() => {
  // App组件已挂载
});

onUnmounted(() => {
  // 确保在组件卸载时清理所有定时器
  stopUpdate();
});
</script>

<template>
  <div class="min-h-screen bg-background text-foreground transition-colors duration-300 flex flex-col">
    <!-- 背景装饰 -->
    <div class="bg-decorative"></div>
    
    <!-- 导航栏 -->
    <nav class="nav-header backdrop-blur-md bg-background/80 border-b border-border">
      <div class="container mx-auto px-4 h-16 flex items-center justify-between">
        <div class="flex items-center gap-3 cursor-pointer" @click="resetToInitial">
          <div class="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
            <svg class="w-5 h-5 text-primary-foreground" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
            </svg>
          </div>
          <div>
            <h1 class="text-xl font-bold">网盘搜索-未来传媒-专注中年人</h1>
          </div>
        </div>
        
        <!-- 导航菜单 -->
        <nav class="flex items-center gap-2" v-if="currentPage === 'search'">
            <a href="https://www.futuremedia.work/tag.html#身心健康">身心健康</a>
            <a href="https://www.futuremedia.work/tag.html#投资理财">投资理财</a>
            <a href="https://www.futuremedia.work/tag.html#学习成长">学习成长</a>
            <a href="https://www.futuremedia.work/tag.html#潮流工具">潮流工具</a>
            <a href="https://www.futuremedia.work/tag.html#其他话题">其他话题</a>
            <a href="https://www.futuremedia.work/about.html">关于本站</a>
          <button 
            @click="switchToDocs"
            class="nav-button"
          >
            <a href="https://www.futuremedia.work/" title="首页" style="text-decoration: none; color: inherit;">
    <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor" style="vertical-align: middle;">
        <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8h5z"></path>
    </svg>
</a>
          </button>
        </nav>
      </div>
    </nav>
    
    <!-- 主要内容区域 -->
    <main class="container mx-auto px-4 py-8 flex-1">
      <!-- 搜索页面 -->
      <div v-if="currentPage === 'search'" class="search-page">
        <!-- 搜索表单 -->
        <div class="mb-6">
          <SearchForm 
            @search="handleSearch" 
            @search-complete="handleSearchComplete"
          />
        </div>
        
        <!-- 搜索统计 -->
        <div v-if="hasSearched || loading" class="mb-6">
          <SearchStats 
            :total="searchResults.total || 0" 
            :mergedResults="searchResults.mergedResults || {}" 
            :loading="loading"
            :searchTime="searchTime"
            :isUpdating="isUpdating"
            :updateCount="updateCount"
          />
        </div>
        
        <!-- 加载状态 -->
        <div v-if="loading" class="card p-6">
          <div class="space-y-3">
            <div class="h-4 bg-muted rounded animate-pulse"></div>
            <div class="h-4 bg-muted rounded animate-pulse w-3/4"></div>
            <div class="h-4 bg-muted rounded animate-pulse w-1/2"></div>
            <div class="h-4 bg-muted rounded animate-pulse w-2/3"></div>
            <div class="h-4 bg-muted rounded animate-pulse"></div>
          </div>
        </div>
        
        <!-- 搜索结果 -->
        <div v-else>
          <ResultTabs 
            :mergedResults="searchResults.mergedResults || {}" 
            :loading="loading"
            :hasSearched="hasSearched"
            :isActivelySearching="isActivelySearching"
          />
        </div>
      </div>
      
      <!-- 状态页面 -->
      <div v-else-if="currentPage === 'status'" class="status-page">
        <ApiStatus />
      </div>
      
      <!-- API文档页面 -->
      <div v-else-if="currentPage === 'docs'" class="docs-page">
        <ApiDocs />
      </div>
    </main>
    
    <!-- 页脚 -->
<footer class="border-t border-border bg-background/50 backdrop-blur-sm mt-auto text-center">
  <div id="footer">
    <div id="footer1">
      Copyright all reserved © 2025-future 
      <a href="https://www.futuremedia.work">未来传媒</a><br>
      <a href="https://www.futuremedia.work/about.html">关于本站</a> |
      <a href="https://www.futuremedia.work/terms-of-service.html">服务条款</a> |  
      <a href="https://www.futuremedia.work/privacy-policy.html">隐私政策</a> |
      <a href="https://www.futuremedia.work/disclaimer.html">免责声明</a> 
    </div>
    <div id="footer2">
      
      <span>Futuremedia.Work-专注中年人 本站由<a href="https://www.futuremedia.work/cdn-cgi/l/email-protection#553320212027303830313c3467656c65153238343c397b363a38" target="_blank">疯子</a>维护</span>
    </div>
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

.nav-header {
  position: sticky;
  top: 0;
  z-index: 50;
}

/* 导航按钮样式 */
.nav-button {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 1rem;
  background: transparent;
  color: hsl(var(--muted-foreground));
  border: 1px solid hsl(var(--border));
  border-radius: 0.375rem;
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s ease;
}

.nav-button:hover {
  background: hsl(var(--accent));
  color: hsl(var(--accent-foreground));
  border-color: hsl(var(--accent));
}



.nav-icon {
  font-size: 1rem;
}

/* 页面切换动画 */
.search-page, .status-page {
  animation: fadeIn 0.3s ease-in-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (max-width: 768px) {
  .container {
    padding-left: 1rem;
    padding-right: 1rem;
  }
  
  .nav-button {
    padding: 0.375rem 0.75rem;
    font-size: 0.8rem;
  }
  
  .nav-icon {
    font-size: 0.875rem;
  }
}

/* 页脚按钮样式 */
footer button {
  background: transparent;
  border: none;
  padding: 0;
  font-size: inherit;
  color: inherit;
  cursor: pointer;
}
  #footer {
  text-align: center;
}

</style>

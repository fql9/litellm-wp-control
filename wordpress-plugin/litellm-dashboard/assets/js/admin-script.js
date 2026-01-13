// LiteLLM Dashboard JavaScript

jQuery(document).ready(function($) {
    'use strict';
    
    // 初始化
    init();
    
    function init() {
        if ($('#litellm-dashboard-container').length) {
            loadDashboardData();
            setInterval(loadDashboardData, 30000); // 每30秒刷新一次
        }
        
        if ($('#litellm-create-key-form').length) {
            handleKeyCreation();
            loadKeys();
        }
        
        if ($('#litellm-settings-form').length) {
            handleSettingsSave();
        }
    }
    
    // 加载仪表盘数据
    function loadDashboardData() {
        $.ajax({
            url: litellmConfig.ajaxUrl,
            type: 'POST',
            data: {
                action: 'litellm_get_stats',
                nonce: litellmConfig.nonce
            },
            success: function(response) {
                if (response.success) {
                    updateStats(response.data);
                    updateCharts(response.data);
                }
            },
            error: function(error) {
                console.error('Failed to load dashboard data:', error);
            }
        });
    }
    
    // 更新统计数据
    function updateStats(data) {
        $('#stat-requests').text(data.total_requests || 0);
        $('#stat-tokens').text(data.total_tokens || 0);
        $('#stat-cost').text('$' + (data.total_cost || 0).toFixed(2));
        $('#stat-error-rate').text((data.error_rate || 0).toFixed(2) + '%');
    }
    
    // 更新图表
    function updateCharts(data) {
        // 请求趋势图
        var requestCtx = document.getElementById('requestChart');
        if (requestCtx) {
            new Chart(requestCtx, {
                type: 'line',
                data: {
                    labels: ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5', 'Day 6', 'Day 7'],
                    datasets: [{
                        label: 'API 请求数',
                        data: data.daily_requests || [0, 0, 0, 0, 0, 0, 0],
                        borderColor: '#0073aa',
                        backgroundColor: 'rgba(0, 115, 170, 0.1)',
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: {
                            display: true,
                            position: 'top',
                        }
                    }
                }
            });
        }
        
        // 成本分布图
        var costCtx = document.getElementById('costChart');
        if (costCtx) {
            new Chart(costCtx, {
                type: 'doughnut',
                data: {
                    labels: data.models || ['Model 1', 'Model 2', 'Model 3'],
                    datasets: [{
                        data: data.model_costs || [30, 40, 30],
                        backgroundColor: [
                            '#0073aa',
                            '#61afd9',
                            '#92c5e9'
                        ]
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: {
                            display: true,
                            position: 'bottom',
                        }
                    }
                }
            });
        }
    }
    
    // 处理 API Key 创建
    function handleKeyCreation() {
        $('#litellm-create-key-form').on('submit', function(e) {
            e.preventDefault();
            
            $.ajax({
                url: litellmConfig.ajaxUrl,
                type: 'POST',
                data: {
                    action: 'litellm_create_key',
                    nonce: litellmConfig.nonce,
                    key_name: $('#key_name').val(),
                    key_models: $('#key_models').val(),
                    key_budget: $('#key_budget').val(),
                    key_rpm: $('#key_rpm').val()
                },
                success: function(response) {
                    if (response.success) {
                        alert('API Key created successfully!');
                        $('#litellm-create-key-form')[0].reset();
                        loadKeys();
                    } else {
                        alert('Error: ' + response.data);
                    }
                },
                error: function(error) {
                    alert('Failed to create key');
                    console.error(error);
                }
            });
        });
    }
    
    // 加载密钥列表
    function loadKeys() {
        $.ajax({
            url: litellmConfig.ajaxUrl,
            type: 'POST',
            data: {
                action: 'litellm_list_keys',
                nonce: litellmConfig.nonce
            },
            success: function(response) {
                if (response.success) {
                    displayKeys(response.data);
                }
            },
            error: function(error) {
                console.error('Failed to load keys:', error);
            }
        });
    }
    
    // 显示密钥列表
    function displayKeys(keys) {
        var html = '';
        if (keys && keys.length > 0) {
            keys.forEach(function(key) {
                html += '<tr>';
                html += '<td>' + (key.key_name || 'N/A') + '</td>';
                html += '<td><code>' + (key.key || 'N/A').substring(0, 20) + '...</code></td>';
                html += '<td>' + (key.status || 'active') + '</td>';
                html += '<td>$' + (key.max_budget || 0).toFixed(2) + '</td>';
                html += '<td>';
                html += '<button class="button delete-key" data-key="' + (key.key || '') + '">Delete</button>';
                html += '</td>';
                html += '</tr>';
            });
        } else {
            html = '<tr><td colspan="5">No keys found</td></tr>';
        }
        
        $('#litellm-keys-list').html(html);
        
        // 绑定删除事件
        $('.delete-key').on('click', function() {
            if (confirm('Are you sure you want to delete this key?')) {
                deleteKey($(this).data('key'));
            }
        });
    }
    
    // 删除密钥
    function deleteKey(key) {
        $.ajax({
            url: litellmConfig.ajaxUrl,
            type: 'POST',
            data: {
                action: 'litellm_delete_key',
                nonce: litellmConfig.nonce,
                key: key
            },
            success: function(response) {
                if (response.success) {
                    alert('Key deleted successfully');
                    loadKeys();
                } else {
                    alert('Error: ' + response.data);
                }
            },
            error: function(error) {
                alert('Failed to delete key');
                console.error(error);
            }
        });
    }
    
    // 处理设置保存
    function handleSettingsSave() {
        $('#litellm-settings-form').on('submit', function(e) {
            e.preventDefault();
            
            $.ajax({
                url: litellmConfig.ajaxUrl,
                type: 'POST',
                data: {
                    action: 'litellm_save_settings',
                    nonce: litellmConfig.nonce,
                    api_base: $('#api_base').val(),
                    master_key: $('#master_key').val(),
                    enabled: $('#enabled').is(':checked') ? 1 : 0
                },
                success: function(response) {
                    if (response.success) {
                        alert('Settings saved successfully!');
                    } else {
                        alert('Error: ' + response.data);
                    }
                },
                error: function(error) {
                    alert('Failed to save settings');
                    console.error(error);
                }
            });
        });
    }
});


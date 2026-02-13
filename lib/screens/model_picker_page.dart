import 'package:flutter/material.dart';
import 'package:doable_todo_list_app/services/openrouter_client.dart';

class ModelPickerPage extends StatefulWidget {
  const ModelPickerPage({super.key});

  @override
  State<ModelPickerPage> createState() => _ModelPickerPageState();
}

class _ModelPickerPageState extends State<ModelPickerPage> {
  List<OpenRouterModel> _allModels = [];
  List<OpenRouterModel> _filteredModels = [];
  bool _loading = true;
  String? _currentModel;
  String _searchQuery = '';
  
  String _priceFilter = 'all'; 
  String _sortBy = 'top'; 
  Set<String> _selectedProviders = {};

  final List<String> _providers = [
    'Google', 'Anthropic', 'OpenAI', 'Qwen', 'DeepSeek', 
    'Meta', 'Mistral', 'NVIDIA', 'xAI', 'Perplexity', 'Amazon', 'Other'
  ];

  final Map<String, IconData> _providerIcons = {
    'Google': Icons.search,
    'Anthropic': Icons.psychology,
    'OpenAI': Icons.smart_toy,
    'Qwen': Icons.auto_awesome,
    'DeepSeek': Icons.bolt,
    'Meta': Icons.facebook,
    'Mistral': Icons.cloud,
    'NVIDIA': Icons.memory,
    'xAI': Icons.rocket_launch,
    'Perplexity': Icons.lightbulb,
    'Amazon': Icons.cloud_queue,
    'Other': Icons.more_horiz,
  };

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    _currentModel = await OpenRouterClient.getModel();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() => _loading = true);
    final models = await OpenRouterClient.fetchModels();
    setState(() {
      _allModels = models;
      _applyFilters();
      _loading = false;
    });
  }

  void _applyFilters() {
    List<OpenRouterModel> result = List.from(_allModels);

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((m) => 
        m.name.toLowerCase().contains(query) || 
        m.id.toLowerCase().contains(query) ||
        (m.description?.toLowerCase().contains(query) ?? false)
      ).toList();
    }

    if (_priceFilter == 'free') {
      result = result.where((m) => m.isFree).toList();
    } else if (_priceFilter == 'paid') {
      result = result.where((m) => m.isPaid).toList();
    }

    if (_selectedProviders.isNotEmpty) {
      result = result.where((m) => _selectedProviders.contains(m.provider)).toList();
    }

    if (_sortBy == 'top') {
      result.sort((a, b) {
        if (a.top && !b.top) return -1;
        if (!a.top && b.top) return 1;
        return a.name.compareTo(b.name);
      });
    } else if (_sortBy == 'name') {
      result.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortBy == 'context') {
      result.sort((a, b) => (b.contextLength ?? 0).compareTo(a.contextLength ?? 0));
    }

    setState(() => _filteredModels = result);
  }

  Future<void> _selectModel(OpenRouterModel model) async {
    await OpenRouterClient.setModel(model.id);
    if (!mounted) return;
    Navigator.pop(context, model);
  }

  Color _getProviderColor(String provider) {
    switch (provider) {
      case 'Google': return Colors.blue;
      case 'Anthropic': return Colors.orange;
      case 'OpenAI': return Colors.green;
      case 'Qwen': return Colors.cyan;
      case 'DeepSeek': return Colors.purple;
      case 'Meta': return Colors.indigo;
      case 'Mistral': return Colors.teal;
      case 'NVIDIA': return Colors.green;
      case 'xAI': return Colors.black;
      case 'Perplexity': return Colors.red;
      case 'Amazon': return Colors.amber;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Model',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: _loading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadModels,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() { _searchQuery = v; _applyFilters(); }),
                  decoration: InputDecoration(
                    hintText: 'Search models...',
                    hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                    prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF262626) : const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _priceFilter == 'all',
                        onTap: () => setState(() { _priceFilter = 'all'; _applyFilters(); }),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Free',
                        selected: _priceFilter == 'free',
                        onTap: () => setState(() { _priceFilter = 'free'; _applyFilters(); }),
                        isDark: isDark,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Paid',
                        selected: _priceFilter == 'paid',
                        onTap: () => setState(() { _priceFilter = 'paid'; _applyFilters(); }),
                        isDark: isDark,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 16),
                      Container(width: 1, height: 24, color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                      const SizedBox(width: 16),
                      _SortChip(
                        label: 'Top',
                        icon: Icons.star,
                        selected: _sortBy == 'top',
                        onTap: () => setState(() { _sortBy = 'top'; _applyFilters(); }),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _SortChip(
                        label: 'A-Z',
                        icon: Icons.sort_by_alpha,
                        selected: _sortBy == 'name',
                        onTap: () => setState(() { _sortBy = 'name'; _applyFilters(); }),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _SortChip(
                        label: 'Context',
                        icon: Icons.memory,
                        selected: _sortBy == 'context',
                        onTap: () => setState(() { _sortBy = 'context'; _applyFilters(); }),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _providers.length,
                    itemBuilder: (_, i) {
                      final provider = _providers[i];
                      final isSelected = _selectedProviders.contains(provider);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(provider),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedProviders.add(provider);
                              } else {
                                _selectedProviders.remove(provider);
                              }
                              _applyFilters();
                            });
                          },
                          avatar: Icon(
                            _providerIcons[provider],
                            size: 16,
                            color: isSelected ? Colors.white : _getProviderColor(provider),
                          ),
                          selectedColor: _getProviderColor(provider),
                          backgroundColor: isDark ? const Color(0xFF262626) : Colors.white,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.black87),
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: isSelected ? _getProviderColor(provider) : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${_filteredModels.length} models',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_selectedProviders.isNotEmpty || _priceFilter != 'all' || _searchQuery.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() {
                      _priceFilter = 'all';
                      _sortBy = 'top';
                      _selectedProviders.clear();
                      _searchQuery = '';
                      _applyFilters();
                    }),
                    child: Text(
                      'Clear filters',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredModels.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredModels.length,
                        itemBuilder: (_, i) => _ModelCard(
                          model: _filteredModels[i],
                          isSelected: _filteredModels[i].id == _currentModel,
                          onTap: () => _selectModel(_filteredModels[i]),
                          isDark: isDark,
                          getProviderColor: _getProviderColor,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 64, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No models found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? chipColor : (isDark ? const Color(0xFF262626) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? chipColor : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.black87),
          ),
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected 
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              size: 14, 
              color: selected 
                  ? Theme.of(context).colorScheme.primary 
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected 
                    ? Theme.of(context).colorScheme.primary 
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final OpenRouterModel model;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;
  final Color Function(String) getProviderColor;

  const _ModelCard({
    required this.model,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
    required this.getProviderColor,
  });

  @override
  Widget build(BuildContext context) {
    final providerColor = getProviderColor(model.provider);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected 
              ? Theme.of(context).colorScheme.primary 
              : (isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE5E7EB)),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: providerColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  color: providerColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            model.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (model.top)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 10, color: Colors.amber),
                                SizedBox(width: 2),
                                Text(
                                  'Top',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: providerColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            model.provider,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: providerColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (model.isFree)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Free',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          )
                        else if (model.pricing != null)
                          Text(
                            model.pricing!,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        if (model.contextLength != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.memory,
                            size: 12,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _formatContextLength(model.contextLength!),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary 
                    : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatContextLength(int length) {
    if (length >= 1000000) {
      return '${(length / 1000000).toStringAsFixed(0)}M';
    } else if (length >= 1000) {
      return '${(length / 1000).toStringAsFixed(0)}K';
    }
    return length.toString();
  }
}

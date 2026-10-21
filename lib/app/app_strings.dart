import '../domain/labels.dart';
import 'shortcuts.dart';

/// The product name shown in the app UI and desktop bundles.
const String kAppName = 'Particle Library';

/// All user-facing UI copy. Data text (PDG descriptions, titles, citations) is
/// never translated automatically.
class AppStrings {
  const AppStrings(this.lang);

  final TextLang lang;

  bool get isZh => lang == TextLang.zh;
  String _t(String zh, String en) => isZh ? zh : en;

  String get appName => kAppName;
  String get appTagline =>
      _t('PDG 粒子数据与综述，离线可查', 'Offline PDG data and reviews');

  String get navQuery => _t('查询', 'Search');
  String get navFavorites => _t('收藏', 'Favorites');
  String get navNotes => _t('笔记', 'Notes');
  String get navSettings => _t('设置', 'Settings');
  String get moreActions => _t('更多', 'More');
  String get editionLabel => _t('PDG 版本', 'PDG edition');
  String get offlineLabel => _t('离线数据', 'Offline data');

  String get searchHint => _t(
    '搜索粒子、性质、PDG 标识符、衰变、文献题名或 DOI',
    'Search particles, properties, PDG identifiers, decays, reference titles or DOIs',
  );
  String get searchShortHint => _t(
    '搜索名称、PDG ID、文献题名或 DOI',
    'Search names, PDG IDs, reference titles or DOIs',
  );
  String get searchButton => _t('搜索', 'Search');
  String get searchExamples => _t(
    '例如 π⁰、proton、B_s0、S032、J/ψ、10.1103/PhysRevD.98.030001',
    'e.g. π⁰, proton, B_s0, S032, J/ψ, 10.1103/PhysRevD.98.030001',
  );
  String get searchEmptyPrompt => _t(
    '输入名称、PDG 标识符、专题词或 DOI/INSPIRE 标识符。',
    'Enter a name, PDG identifier, topic word, or DOI/INSPIRE identifier.',
  );
  String get searchRecent => _t('最近查询', 'Recent searches');
  String get searchRemoveRecent => _t('移除此记录', 'Remove this search');
  String get searchClearRecent => _t('清除最近查询', 'Clear recent searches');
  String get searchClearRecentConfirm =>
      _t('清除全部最近查询记录？此操作只影响本机。', 'Clear all recent searches on this device?');
  String get searchNoRecent => _t('尚无最近查询。', 'No recent searches yet.');
  String get searchNoResults => _t(
    '没有找到匹配项。请检查写法或切换搜索范围。',
    'No matches. Check the spelling or change the scope.',
  );
  String get searchFailed => _t('搜索失败。', 'Search failed.');
  String get searchLoading => _t('正在搜索…', 'Searching…');
  String get searchShowingFirst =>
      _t('仅显示前若干项', 'Showing the first matches only');
  String get searchResultCount => _t('结果', 'Results');
  String get searchIdAccepted =>
      _t('识别为 PDG 标识符', 'Recognized as a PDG identifier');
  String get searchMcNumber => _t('MC 编号', 'MC number');
  String get searchScopeAll => _t('全部', 'All');
  String get searchScopeParticles => _t('粒子', 'Particles');
  String get searchScopeTitles => _t('性质 / 专题', 'Properties / topics');
  String get searchScopeDecays => _t('衰变', 'Decays');
  String get searchScopeReferences => _t('文献', 'References');
  String get searchScopeNotes => _t('笔记', 'Notes');
  String get searchKindIdentifier => _t('标识符', 'Identifier');
  String get searchKindParticle => _t('粒子', 'Particles');
  String get searchKindTopic => _t('条目与专题', 'Entries & topics');
  String get searchKindDecay => _t('衰变模式', 'Decay modes');
  String get searchKindReference => _t('文献', 'References');
  String get searchKindText => _t('说明文本', 'Section text');
  String get searchKindNote => _t('笔记', 'Notes');

  String get bootLoading =>
      _t('正在打开离线 PDG 数据…', 'Opening the offline PDG data…');
  String get bootVerifying =>
      _t('正在校验数据库完整性…', 'Verifying database integrity…');
  String get bootFirstRun =>
      _t('首次启动，正在复制随包数据库…', 'First launch: copying the bundled database…');
  String get bootFailed => _t('无法打开数据', 'Could not open the data');
  String get bootRetry => _t('重试', 'Retry');
  String get bootDetails => _t('错误详情', 'Error details');

  String get commonBack => _t('返回', 'Back');
  String get commonForward => _t('前进', 'Forward');
  String get commonClose => _t('关闭', 'Close');
  String get commonCancel => _t('取消', 'Cancel');
  String get commonCreate => _t('创建', 'Create');
  String get commonSave => _t('保存', 'Save');
  String get pageOutline => _t('页面目录', 'On this page');
  String get pageOverview => _t('概要', 'Overview');
  String get pageIdentity => _t('身份', 'Identity');
  String get pageKeyProperties => _t('关键性质', 'Key properties');
  String get pageNotes => _t('笔记', 'Notes');
  String get pageTexts => _t('说明', 'Text');
  String get commonDelete => _t('删除', 'Delete');
  String get commonConfirm => _t('确定', 'OK');
  String get commonClear => _t('清除', 'Clear');
  String get commonCopy => _t('复制', 'Copy');
  String get commonNothingToCopy => _t('没有可复制的内容', 'Nothing to copy');
  String get commonCopyFailed => _t('复制失败', 'Copy failed');
  String get commonSelectAll => _t('全选', 'Select all');
  String get commonCopied => _t('已复制到剪贴板', 'Copied to clipboard');
  String get commonAll => _t('全部', 'All');
  String get commonNone => _t('无', 'None');
  String get commonUnknown => _t('状态未知', 'Unknown');
  String get commonNotRecorded => _t('未收录', 'Not in this snapshot');
  String get commonNotStated => _t('未注明', 'Not stated');
  String get commonNull => _t('NULL', 'NULL');
  String get commonEmptyString => _t('空字符串', 'Empty string');
  String get commonLoading => _t('正在读取…', 'Loading…');
  String get commonError => _t('读取失败', 'Failed to load');
  String get commonRetry => _t('重试', 'Retry');
  String get commonRawFields => _t('原始字段', 'Raw fields');
  String get commonRawRecord => _t('原始记录', 'Source record');
  String get commonShowRaw => _t('查看原始字段', 'Show raw fields');
  String get commonHideRaw => _t('收起原始字段', 'Hide raw fields');
  String get commonCopyRaw => _t('复制全部原始字段', 'Copy all raw fields');
  String get commonSource => _t('来源', 'Source');
  String get commonShowMore => _t('展开更多', 'Show more');
  String get commonShowLess => _t('收起', 'Show less');
  String get commonViewAll => _t('查看全部', 'View all');
  String get commonOpen => _t('打开', 'Open');
  String get commonDetails => _t('详情', 'Details');
  String get commonCount => _t('数量', 'Count');
  String get commonYear => _t('年份', 'Year');
  String get commonToday => _t('本次', 'This session');
  String get commonSnapshot => _t('数据快照', 'Snapshot');
  String get commonEdition => _t('版次', 'Edition');
  String get commonNoData => _t('没有可显示的数据', 'No displayable data');
  String get commonNotApplicable => _t('不适用', 'Not applicable');
  String get commonUninterpreted => _t('未解释', 'Uninterpreted');
  String get commonFilter => _t('筛选', 'Filter');
  String get commonReset => _t('重置', 'Reset');
  String get commonApply => _t('应用', 'Apply');
  String get commonMoreOptions => _t('更多', 'More');
  String get commonSort => _t('排序', 'Sort');
  String get commonExact => _t('精确', 'Exact');

  String get rawRecordHint => _t(
    '以下为数据库原始列；NULL、空字符串与 0 分别保留。',
    'Database columns as stored; NULL, the empty string and 0 remain distinct.',
  );
  String get nullValue => 'NULL';
  String get emptyStringValue => _t('空字符串', 'empty string');

  String get catalogTitle => _t('全库目录', 'Full catalog');
  String get catalogSubtitle => _t(
    '所有根条目，包括没有粒子身份行的专题',
    'All root entries, including topics without a particle identity row',
  );
  String get catalogRoots => _t('根条目', 'Root entries');
  String get entriesLabel => _t('条目', 'entries');
  String get summariesLabel => _t('当版汇总', 'current summaries');
  String get measurementsLabel => _t('测量记录', 'measurement records');
  String get referencesLabel => _t('文献', 'references');
  String get summaryCountLabel => _t('条汇总', 'summary rows');
  String get relatedQuantitiesLabel => _t('个相关量', 'related quantities');
  String get unnamedColumn => _t('未命名列', 'Unnamed column');
  String get catalogChildren => _t('子条目', 'Children');
  String get catalogNoChildren =>
      _t('该条目没有子条目。', 'This entry has no children.');
  String get catalogCategory => _t('分类', 'Category');
  String get catalogUncategorized => _t('分类未确定', 'Uncategorized');
  String get catalogSearch => _t('在目录中筛选…', 'Filter the catalog…');
  String get catalogOpenRoot => _t('打开根条目', 'Open root entry');
  String get sidebarTitle => _t('上下文', 'Context');
  String get sidebarNotes => _t('笔记', 'Notes');
  String get sidebarShow => _t('显示侧边栏', 'Show sidebar');
  String get sidebarHide => _t('隐藏侧边栏', 'Hide sidebar');
  String get sidebarType => _t('类型', 'Type');
  String get sidebarEdition => _t('当前版本', 'Edition');
  String get sidebarSummaries => _t('当前汇总', 'Current summaries');
  String get sidebarMeasurements => _t('测量', 'Measurements');
  String get sidebarHistory => _t('历史版本', 'Editions in history');
  String get sidebarSeeAlso => _t('参见', 'See also');
  String get sidebarParents => _t('上级条目', 'Parent entries');
  String get sidebarSiblings => _t('同章节条目', 'Sibling entries');
  String get sidebarChildren => _t('子条目', 'Children');
  String get sidebarSummariesShort => _t('汇总', 'summaries');
  String get sidebarIdentities => _t('身份', 'Identities');
  String get sidebarProperties => _t('性质', 'Properties');
  String get sidebarDecays => _t('衰变模式', 'Decay modes');
  String get sidebarReferences => _t('文献', 'References');

  String get particleMissingIdentity => _t(
    '该条目是 PDG 搜索/专题或节标题，当前快照没有粒子身份行；它只汇总测量数据，不包含正文。相关小综述请在 Reviews 中查看。',
    'This is a PDG search/topic or section heading without a particle identity row in this snapshot. It aggregates measurements and has no prose of its own; related review articles are in Reviews.',
  );
  String particleAlsoKnownAs(String alias) =>
      _t('又称 $alias', 'Also known as $alias');
  String get particleAliasSource => _t('PDG listing', 'PDG listing');
  String get particleSharedListing => _t(
    '这些粒子身份共享同一个 listing；测量记录按 listing 收录，电荷以原始记录为准。',
    'These identities share one listing. Measurements are stored for the listing; the raw charge field is shown unchanged.',
  );
  String get particleIdentity => _t('粒子身份', 'Particle identity');
  String get particleCharge => _t('电荷', 'Charge');
  String get particleMcId => _t('MC 编号', 'MC ID');
  String get particleAntiparticle => _t('反粒子', 'Antiparticle');
  String get particleSelfConjugate => _t('自共轭', 'Self-conjugate');
  String get particleQuantumNumbers => _t('量子数（原始字段）', 'Quantum numbers (raw)');
  String get particleProperties => _t('性质', 'Properties');
  String get particleDecays => _t('衰变', 'Decays');
  String get particleReferences => _t('文献', 'References');
  String get particleMainProperties => _t('主要性质', 'Key properties');
  String get particleNoMainProperties => _t(
    '该粒子没有可显示的质量、宽度或寿命汇总。',
    'No mass, width or lifetime summary is recorded for this particle.',
  );
  String get particlePropertyDirectory =>
      _t('全部性质目录', 'Complete property directory');
  String get particlePropertyDirectoryHint => _t(
    '按原始章节与类型排列；未知类型也保留入口。',
    'Grouped as published; uninterpreted types remain reachable.',
  );
  String get particleNoProperties =>
      _t('该 listing 下没有可显示的性质条目。', 'No property entries under this listing.');
  String get particleNoDecays =>
      _t('该 listing 下没有衰变模式条目。', 'No decay-mode entries under this listing.');
  String get particleReferenceCount => _t('篇文献', 'references');
  String get particleListingId => _t('listing', 'listing');
  String get particleIdentityCount => _t('个身份', 'identities');

  String get seriesDefinition => _t('定义与来源', 'Definition and source');
  String get seriesCurrentSummaries =>
      _t('当前版 PDG 汇总', 'Current PDG summaries');
  String get seriesNoSummary => _t(
    '当前版未收录该系列的 PDG 汇总。',
    'No current-edition summary is recorded for this series.',
  );
  String get seriesPreferred => _t('官方首选', 'Official preferred');
  String get seriesMultipleCandidates => _t(
    '存在多个候选汇总，未选出唯一首选；全部候选均保留。',
    'Several summary candidates; no unique preferred row. All candidates are retained.',
  );
  String get seriesNoPreferred => _t('无唯一首选', 'No unique preferred row');
  String get seriesCandidates => _t('候选汇总', 'Summary candidates');
  String get seriesInSummaryTable => _t('Summary Table', 'Summary Table');
  String get seriesNotInSummaryTable =>
      _t('不在 Summary Table', 'Not in Summary Table');
  String get seriesValueType => _t('取得方式', 'Value type');
  String get seriesScaleFactor => _t('误差调整因子', 'Scale factor');
  String get seriesConfidence => _t('置信水平', 'Confidence level');
  String get seriesComment => _t('说明', 'Comment');
  String get seriesMeasurements => _t('完整测量', 'Complete measurements');
  String get seriesMeasurementCount => _t('条测量记录', 'measurement records');
  String get seriesNoMeasurements => _t(
    '当前快照没有该系列的直接测量记录。',
    'This snapshot records no direct measurements for this series.',
  );
  String get seriesMeasurementsViaRelated => _t(
    '本条目没有直接测量；相关量的测量可从下方进入。',
    'No direct measurements for this entry; measurements of related quantities are linked below.',
  );
  String get seriesLoadMore => _t('加载更多测量', 'Load more measurements');
  String get seriesShowingMeasurements => _t('已显示测量', 'Measurements shown');
  String get seriesFilterAverage => _t('average 标志', 'average flag');
  String get seriesFilterFit => _t('fit 标志', 'fit flag');
  String get seriesFilterLimit => _t('结果类型', 'Result type');
  String get seriesFilterChanged => _t('仅当版修订', 'Changed in this edition only');
  String get seriesFilterAny => _t('不限', 'Any');
  String get seriesFilterYes => _t('是', 'Yes');
  String get seriesFilterNo => _t('否', 'No');
  String get seriesFilterUnknown => _t('未注明', 'Not stated');
  String get seriesFilterPoint => _t('测量值', 'Measured value');
  String get seriesFilterUpper => _t('上限', 'Upper limit');
  String get seriesFilterLower => _t('下限', 'Lower limit');
  String get seriesFilterRange => _t('区间', 'Range');
  String get seriesFilterExclusion => _t('排除区间', 'Exclusion range');
  String get seriesFilterHint => _t(
    '筛选使用 pdgmeasurement_values.used_in_average / used_in_fit（每个数值列在本 listing 汇总表计算中的纳入标志）；这不是 PDG 汇总类型 OUR AVERAGE / OUR FIT。命中一列时仍显示整条测量的全部列。',
    'Filters use pdgmeasurement_values.used_in_average / used_in_fit (whether this value column entered this listing’s Summary-Table average or fit). These are not the PDG summary types OUR AVERAGE / OUR FIT. A matching column keeps the whole measurement visible.',
  );
  String get summaryTypeLabel => _t('汇总类型', 'Summary type');
  String get measurementFlagNote => _t(
    '本标志来自测量值列的 used_in_average / used_in_fit，只表示本 listing 的汇总表计算；不是 pdgdata.value_type 的 OUR AVERAGE / OUR FIT。',
    'This flag is the value column’s used_in_average / used_in_fit for this listing’s Summary-Table calculation; it is not the pdgdata.value_type OUR AVERAGE / OUR FIT.',
  );
  String get seriesHistory => _t('历史汇总', 'Historical summaries');
  String get seriesHistoryCount => _t('条历史汇总记录', 'historical summary rows');
  String get seriesNoHistory =>
      _t('该系列没有历史汇总记录。', 'No historical summary rows for this series.');
  String get seriesHistoryHint => _t(
    '只列出该系列实际存在的版次；同一版次的多行全部保留。',
    'Only editions actually present are listed; every row of an edition is retained.',
  );
  String get seriesTrendChart => _t('趋势图', 'Trend chart');
  String get seriesTrendTitle => _t('跨版趋势', 'Across PDG editions');
  String get seriesTrendSubtitle => _t(
    '同一量的 PDG 汇总随版本变化；误差条为原始正、负误差。',
    'The PDG summary of one quantity across editions; error bars are the raw positive and negative errors.',
  );
  String get seriesTrendNoData => _t(
    '至少需要两个版本的数值才能绘制趋势。',
    'At least two editions with a numeric value are needed for a trend.',
  );
  String get seriesTrendUnitMismatch => _t(
    '这些版本的单位不一致，未绘制。',
    'The editions use different units, so no chart is drawn.',
  );
  String get seriesTrendAmbiguous =>
      _t('个版本有并列汇总', 'editions with tied summaries');
  String get seriesTrendLimits => _t('个版本只有限值', 'editions with limits only');
  String get seriesTrendPoints => _t('个版本', 'editions');
  String get seriesTrendXAxis => _t('PDG 版本', 'PDG edition');
  String get seriesTrendYAxis => _t('数值', 'Value');
  String get seriesTrendCurrent => _t('当前版本', 'Current edition');
  String get seriesTrendClose => _t('关闭', 'Close');
  String get seriesSectionText =>
      _t('章节说明与物理约定', 'Section text and conventions');
  String get seriesNoSectionText => _t(
    '该条目及祖先章节没有可显示的说明文本。',
    'No explanatory text is stored for this entry or its ancestors.',
  );
  String get seriesRelatedModes =>
      _t('关联到本量的衰变模式', 'Decay modes linked to this quantity');
  String get seriesNoRelatedModes => _t(
    '没有其他条目通过 pdgid_map 关联到本量。',
    'No other entry is linked to this quantity through pdgid_map.',
  );
  String get seriesCopySummary => _t('复制当前汇总', 'Copy current summary');
  String get seriesCopyDefinition =>
      _t('复制定义与来源', 'Copy definition and source');
  String get seriesCopyMeasurements => _t('复制测量列表', 'Copy measurement list');
  String get seriesFootnotes => _t('本章节脚注', 'Section footnotes');
  String get seriesNoFootnotes => _t(
    '没有以该条目标识精确关联的章节脚注。',
    'No section footnote is associated with this exact entry identifier.',
  );
  String get seriesFootnoteAttachments => _t('挂接的测量', 'Attached measurements');
  String get seriesDefinitionTextHint => _t(
    '文本按数据库原文显示；标题与约定段落分别保留类型。',
    'Text is shown as stored; heading and body text keep their type.',
  );

  String get measurementTitle => _t('测量详情', 'Measurement detail');
  String get measurementPrimaryValue => _t('主值', 'Primary value');
  String get measurementColumns => _t('全部数值列', 'All value columns');
  String get measurementNoColumns =>
      _t('该测量没有数值列记录。', 'No value columns are recorded for this measurement.');
  String get measurementColumn => _t('列名', 'Column');
  String get measurementSourceText => _t('源文本', 'Source text');
  String get measurementDisplay => _t('显示值', 'Display value');
  String get measurementRawValue => _t('原始值', 'Raw value');
  String get measurementUnit => _t('单位', 'Unit');
  String get measurementErrors => _t('误差（原始分量）', 'Errors (raw components)');
  String get measurementStat => _t('统计', 'stat.');
  String get measurementSyst => _t('系统', 'syst.');
  String get measurementTotal => _t('总', 'total');
  String get measurementInclusion => _t('纳入状态', 'Inclusion');
  String get measurementReference => _t('文献', 'Reference');
  String get measurementCharge => _t('charge 原码', 'Raw charge');
  String get measurementEvents => _t('事件数（原文）', 'Event count (raw)');
  String get measurementComment => _t('测量说明', 'Measurement comment');
  String get measurementChangebar => _t('当版新增/修订标记', 'Changed in this edition');
  String get measurementFootnotes => _t('脚注', 'Footnotes');
  String get measurementNoFootnotes =>
      _t('该测量没有脚注附件。', 'No footnote is attached to this measurement.');
  String get measurementNoReference =>
      _t('未收录文献记录', 'No reference row recorded');
  String get measurementTechniqueUninterpreted =>
      _t('PDG technique 代码', 'PDG technique code');
  String measurementPlaceMeaning(String code) {
    final c = code.trim().toUpperCase();
    return switch (c) {
      'U' => _t(
        'U（PDG RedBook PLACE）：used 部分；可作为 average/fit 的候选测量。',
        'U: used portion; a candidate contributor to averages/fits.',
      ),
      'N' => _t(
        'N（PDG RedBook PLACE）：not used 部分；不参与汇总。',
        'N: not-used portion; not used in summaries.',
      ),
      'L' => _t(
        'L（PDG RedBook PLACE）：used 部分的最佳限值，会进入 RESULT SUMMARY。',
        'L: best limit in the used portion; copied to RESULT SUMMARY.',
      ),
      'B' => _t(
        'B（PDG RedBook PLACE）：used 部分的最佳限值，不进入 RESULT SUMMARY。',
        'B: best limit in the used portion; not copied to RESULT SUMMARY.',
      ),
      _ => _t('PDG PLACE 代码：$code', 'PDG PLACE code: $code'),
    };
  }

  String measurementTechniqueExpanded(String raw) => _t(
    'technique 原码：$raw；chip 中显示的是已核对的实验全名。',
    'Raw technique: $raw; the chip shows the verified experiment name.',
  );
  String get measurementOpenReference => _t('打开文献', 'Open reference');
  String get measurementRawHint => _t(
    '所有数值、误差、限值和纳入标志均来自 pdgmeasurement_values 原始行。',
    'All values, errors, limits and inclusion flags come from the raw pdgmeasurement_values row.',
  );
  String get measurementCopy => _t('复制测量与文献', 'Copy measurement and reference');
  String get measurementUsedAverage => _t('average', 'average');
  String get measurementUsedFit => _t('fit', 'fit');
  String get measurementPercentPath => _t(
    '百分显示（原始幂 −2 不再叠加）',
    'Percent display (the implied −2 power is not stacked)',
  );
  String get measurementLimit => _t('结果类型', 'Result type');

  String get decayCatalogTitle => _t('衰变目录', 'Decay catalog');
  String decayMoreModes(int remaining) =>
      _t('显示更多模式（剩余 $remaining）', 'Show more modes ($remaining left)');
  String get decayCatalogHint => _t(
    '按官方条目顺序与缩进显示；展开只改变目录，不重新解释物理阶段。',
    'Official order and indentation; expanding only changes the directory view, not the physical interpretation.',
  );
  String get decaySearchHint =>
      _t('筛选模式原文或产物…', 'Filter mode text or products…');
  String get decayTree => _t('目录', 'Tree');
  String get decayFlat => _t('平铺', 'Flat');
  String get decayExpandAll => _t('展开全部', 'Expand all');
  String get decayCollapseAll => _t('收起全部', 'Collapse all');
  String get decayModeCount => _t('个模式', 'modes');
  String get decayStructurePending => _t('结构待判', 'Structure unresolved');
  String get decayNoModesMatch =>
      _t('没有模式匹配当前筛选。', 'No mode matches the filter.');
  String get decayOriginal => _t('原文', 'Original text');
  String get decayStructure => _t('参与项序列', 'Source token sequence');
  String get decayIncoming => _t('入射', 'Incoming');
  String get decayOutgoing => _t('出射', 'Outgoing');
  String get decayMultiplier => _t('重复数', 'Multiplier');
  String get decayItemType => _t('名称项类型', 'Item type');
  String get decayUnresolved => _t('未解析', 'Unresolved');
  String get decayResolved => _t('已定位', 'Resolved');
  String get decayInclusiveToken =>
      _t('单举项（表示存在未列出的产物）', 'Inclusive item (unlisted products may exist)');
  String get decayTextToken =>
      _t('文本/条件/记号，不能当作粒子', 'Text, condition or punctuation; not a particle');
  String get decayMultiStageNote => _t(
    '原文包含多个阶段箭头；这里按原始顺序展示，不把不同阶段的产物合并成一个末态。',
    'The source contains several stage arrows; tokens are shown in source order and stages are not merged into one final state.',
  );
  String get decayNoOutgoingNote => _t(
    '该条目没有 outgoing 参与项行。原始描述仍然完整保留，不能据此显示空末态。',
    'This entry has no outgoing token rows. The original description is retained; an empty final state is not implied.',
  );
  String get decayDirectoryChildren => _t('目录子项', 'Directory children');
  String get decayNoDirectoryChildren =>
      _t('没有目录子项。', 'No directory children.');
  String get decayRelatedQuantities => _t('相关测量量', 'Related quantities');
  String get decayNoRelated => _t(
    '没有通过 pdgid_map 关联的相关量。',
    'No related quantity is linked through pdgid_map.',
  );
  String get decayRelatedHint => _t(
    '相关量的类型与定义按目标条目原样显示；比值或宽度不能改称本模式的分支分数。',
    'Related quantities keep their own type and definition; a ratio or width is never relabelled as this mode’s branching fraction.',
  );
  String get decayDirectMeasurements =>
      _t('本模式直接测量', 'Direct measurements of this mode');
  String get decayNoDirectMeasurements => _t(
    '本模式在数据库中通常没有直接测量行；相关量的测量如下。',
    'This mode normally has no direct measurement rows; measurements of its related quantities are below.',
  );
  String get decayNoRelatedMeasurements => _t(
    '当前数据库没有为该模式提供相关测量链接。',
    'This snapshot provides no related-measurement link for this mode.',
  );
  String get decaySummary => _t('本模式 PDG 汇总', 'PDG summaries of this mode');
  String get decayModeNumber => _t('当版模式编号', 'Mode number');
  String get decayCopyOriginal => _t('复制衰变原文', 'Copy decay text');
  String get decayCopySummary => _t('复制汇总与条件', 'Copy summary and conditions');
  String get decayCopyRelated =>
      _t('复制相关量与引用', 'Copy related quantities and citations');
  String get decayPath => _t('目录路径', 'Directory path');
  String get decayNoSummary => _t(
    '本模式未收录该版 PDG 汇总。',
    'No current-edition summary is recorded for this mode.',
  );
  String get decayStageNote => _t(
    '目录父子关系不是物理级联：子项表示原文中的细化、排除条件或分组。',
    'Directory parentage is not a physical cascade: children represent refinements, exclusions or groupings in the source.',
  );
  String get decayTokenDetails => _t('名称项身份', 'Item identity');
  String get decayTokenCandidates => _t('候选身份', 'Candidate identities');
  String get decayTokenNoIdentity =>
      _t('没有具体粒子行；保留原文。', 'No particle row; raw text is retained.');
  String get decayTokenConflict => _t(
    '身份多义：同一名称项连接多个 listing。',
    'Ambiguous identity: one item points to several listings.',
  );
  String decayTokenGeneric(int count) =>
      _t('通用名称，展开为 $count 个粒子', 'Generic name; expands to $count particles');

  String get referenceTitle => _t('文献', 'Publication');
  String get inspireSearchTitle => _t('INSPIRE 文献搜索', 'Search INSPIRE');
  String get inspireSearchSubtitle => _t(
    '使用 INSPIRE 语法在线检索文献',
    'Search INSPIRE online with INSPIRE query syntax',
  );
  String get inspireSearchHint => _t(
    '输入 INSPIRE 语法或关键词，例如 cn BESIII、t "muon"',
    'Enter INSPIRE syntax or keywords, e.g. cn BESIII, t "muon"',
  );
  String get inspireSearchAction => _t('搜索 INSPIRE', 'Search INSPIRE');
  String get inspireSearchEntryHint => _t(
    '题名、期刊和年份可离线搜索；作者、合作组和 INSPIRE 语法需联网检索。',
    'Titles, journals and years work offline; authors, collaborations and INSPIRE syntax require the online search.',
  );
  String get inspireSearchOnlineNote => _t(
    '此页需要联网；结果来自 INSPIRE，本地 PDG 文献不受影响。支持 a、t、cn、doi、arxiv 等语法。',
    'This page requires network access. Results come from INSPIRE and do not change local PDG references. Supports a, t, cn, doi, arxiv and other INSPIRE operators.',
  );
  String get inspireSearchEmpty =>
      _t('INSPIRE 没有找到匹配文献。', 'No matching INSPIRE records.');
  String inspireSearchResults(int count) =>
      _t('找到 $count 条 INSPIRE 记录', '$count INSPIRE records');
  String inspireCitations(int count) => _t('引用 $count 次', '$count citations');
  String get inspireFilter => _t('过滤', 'Filter');
  String get inspireFilterHint => _t(
    '过滤当前结果：标题、作者、DOI、arXiv…',
    'Filter these results: title, authors, DOI, arXiv…',
  );
  String get inspireFilterLocal => _t('PDG 中有的', 'In local PDG');
  String get inspireFilterNotLocal => _t('PDG 中没有的', 'Not in local PDG');
  String get inspireFilterZotero => _t('Zotero 中有的', 'In Zotero');
  String get inspireFilterNotZotero => _t('Zotero 中没有的', 'Not in Zotero');
  String get inspireFilterPublished => _t('已发表', 'Published');
  String get inspireFilterPreprint => _t('预印本', 'Preprint');
  String get inspireFilterHighCited => _t('高引用（>100）', 'Highly cited (>100)');
  String get inspireFilterRecent5 => _t('近 5 年', 'Last 5 years');
  String get inspireFilterNoResults =>
      _t('当前页没有符合过滤条件的结果。', 'No results on this page match the filters.');
  String inspireFilteredShowing(int shown, int pageCount) =>
      _t('本页匹配 $shown / $pageCount 条', '$shown / $pageCount on this page');
  String get inspireSortBy => _t('排序', 'Sort');
  String get inspireSortCited => _t('引用最多', 'Most cited');
  String get inspireSortRecent => _t('最新', 'Newest');
  String get inspirePrevious => _t('上一页', 'Previous');
  String get inspireNext => _t('下一页', 'Next');
  String inspirePage(int page, int pages) =>
      _t('第 $page / $pages 页', 'Page $page / $pages');
  String get inspirePageSize => _t('每页', 'Per page');
  String inspirePageSizeValue(int size) => _t('$size 篇', '$size');
  String get inspireLoadMore => _t('加载更多', 'Load more');
  String inspireShowing(int shown, int total) =>
      _t('显示 $shown / $total 条', 'Showing $shown / $total');
  String get inspireSearchNoLocal => _t(
    '本地 PDG 快照没有这个 DOI 的文献记录。',
    'The local PDG snapshot has no record with this DOI.',
  );
  String get inspireSearchOpenLocal =>
      _t('打开本地 PDG 文献记录', 'Open local PDG reference');
  String get inspireSearchSyntaxExamples => _t(
    '支持 INSPIRE 语法：cn BESIII · t "muon" · arxiv:0902.4759 · doi:10.1103/PhysRevLett.6.381',
    'INSPIRE syntax is supported: cn BESIII · t "muon" · arxiv:0902.4759 · doi:10.1103/PhysRevLett.6.381',
  );
  String get inspireSearchOpenLocalHint => _t(
    '“打开本地 PDG 文献记录”表示按 DOI 查找 PDG 快照中的文献条目，不是打开 PDG 网站。',
    '“Open local PDG reference” looks up the PDG snapshot record by DOI; it does not open the PDG website.',
  );
  String get inspireSearchOpenInspire => _t('在 INSPIRE 打开', 'Open in INSPIRE');
  String get inspireZotero => _t('Zotero', 'Zotero');
  String get zoteroOpen => _t('在 Zotero 中查找/打开', 'Find/open in Zotero');
  String get zoteroNotRunning => _t(
    'Zotero 未运行或本地 API 不可用。',
    'Zotero is not running or its local API is unavailable.',
  );
  String get inspireZoteroRetry => _t(
    '在 Zotero 中重新查找（未找到时复制 BibTeX）',
    'Look up in Zotero again (copy BibTeX if still missing)',
  );
  String get inspireAddToZotero => _t('添加到 Zotero', 'Add to Zotero');
  String get inspireAddingToZotero => _t('等待 Zotero…', 'Waiting for Zotero…');
  String get inspireAddedToZotero => _t('已添加到 Zotero', 'Added to Zotero');
  String get inspireAlreadyInZotero => _t('已在 Zotero 中', 'Already in Zotero');
  String get inspireAddToZoteroFailed =>
      _t('添加到 Zotero 失败', 'Could not add to Zotero');
  String get inspireZoteroFind => _t(
    '在 Zotero 中查找（未找到时复制 BibTeX）',
    'Find in Zotero (copy BibTeX if missing)',
  );
  String get inspireZoteroFindOrAdd =>
      _t('Zotero 中已有则打开，没有则添加', 'Open in Zotero if present, add it if missing');
  String get inspireZoteroCacheHint => _t(
    'Zotero 已连接；构建索引可加速大库匹配并启用 Zotero 过滤（设置 → Zotero 条目缓存）。',
    'Zotero is connected. Build the index for faster matching and Zotero filters (Settings → Zotero item cache).',
  );
  String get inspireZoteroNotFoundCopied => _t(
    'Zotero 中没有找到；BibTeX 已复制。',
    'Not found in Zotero; BibTeX copied instead.',
  );
  String get inspireZoteroNotFound => _t(
    'Zotero 中未找到该 recid，已把 BibTeX 复制到剪贴板，可在 Zotero 中导入。',
    'No Zotero item for this recid; BibTeX copied for import in Zotero.',
  );
  String get inspireZoteroAddUnavailable => _t(
    'zotero-inspire 的添加功能不可用；已复制 BibTeX。',
    'zotero-inspire add is unavailable; BibTeX copied.',
  );
  String get inspireZoteroCopied => _t('BibTeX 已复制', 'BibTeX copied');
  String get inspireZoteroFailed => _t('Zotero 联动失败', 'Zotero link failed');
  String get referenceDocuments => _t('文献记录', 'Reference record');
  String get referenceNoTitle => _t(
    '未收录题名（以 document_id 作为标题）',
    'No title recorded (document_id used as the heading)',
  );
  String get referenceLookupTitle => _t('通过 DOI 查询题名', 'Look up title via DOI');
  String get referenceRefreshTitle => _t('重新查询题名', 'Refresh title');
  String get referenceLookupHint => _t(
    '快照未收录题名。可联网向 Crossref 查询题名并缓存在本机；不会修改快照字段。',
    'The snapshot has no title. Optionally look it up at Crossref and cache it locally; the snapshot is not modified.',
  );
  String get referenceLookupRunning => _t('正在查询…', 'Looking up…');
  String get referenceLookupFailed => _t('题名查询失败', 'Title lookup failed');
  String get referenceLookupNoDoi =>
      _t('快照未收录题名，且没有可用的 DOI。', 'No title or usable DOI recorded.');
  String get referenceEnrichedTitle =>
      _t('补充题名（Crossref）', 'Enriched title (Crossref)');
  String get referenceEnrichedNote => _t(
    '题名由 Crossref 补充，原始快照 title 仍为空；结果缓存在本机。',
    'The title is supplied by Crossref; the raw snapshot title remains empty and the result is cached locally.',
  );
  String get referenceDocumentId => _t('document_id', 'document_id');
  String get referencePublication => _t('出版信息（原文）', 'Publication (raw)');
  String get referenceYear => _t('发表年份', 'Publication year');
  String get referenceDoi => _t('DOI', 'DOI');
  String get referenceInspire => _t('INSPIRE 标识符', 'INSPIRE identifier');
  String get referenceOpenDoi => _t('在 DOI 服务打开', 'Open DOI');
  String get referenceOpenInspire => _t('在 INSPIRE 打开', 'Open INSPIRE');
  String get referenceCopyBibtex => _t('复制 BibTeX', 'Copy BibTeX');
  String get referenceCopyBibtexRunning => _t('获取 BibTeX…', 'Fetching BibTeX…');
  String get referenceBibtexCopied => _t('BibTeX 已复制', 'BibTeX copied');
  String get referenceBibtexFailed =>
      _t('BibTeX 获取失败', 'Could not fetch BibTeX');
  String get referenceBibtexNoId => _t(
    '没有 INSPIRE ID 或 DOI，无法可靠获取 BibTeX。',
    'No INSPIRE ID or DOI; a reliable BibTeX entry cannot be fetched.',
  );
  String get referenceSearchInspireDoi =>
      _t('在 INSPIRE 搜索 DOI', 'Search INSPIRE by DOI');
  String get referenceSearchInspireTitle =>
      _t('在 INSPIRE 搜索题名', 'Search INSPIRE by title');
  String get referenceInspireViaDoi =>
      _t('无 INSPIRE 标识符；使用 DOI 搜索。', 'No INSPIRE ID; search by DOI.');
  String get referenceInspireCiteKey =>
      _t('INSPIRE cite key', 'INSPIRE cite key');
  String get referenceInspireViaTitle => _t(
    '无 INSPIRE 标识符或 DOI；使用题名搜索。',
    'No INSPIRE ID or DOI; search by title.',
  );
  String get referenceNoDoi => _t('未收录 DOI。', 'No DOI recorded.');
  String get referenceNoInspire =>
      _t('未收录 INSPIRE 标识符。', 'No INSPIRE identifier recorded.');
  String get referenceReverseMeasurements =>
      _t('反向关联测量', 'Reverse-linked measurements');
  String get particleNoPropertiesMatch =>
      _t('没有性质匹配当前筛选。', 'No property matches the current filter.');
  String get particleNoReferences =>
      _t('该粒子暂无关联文献。', 'No references are linked to this particle.');
  String get referenceNoReverse => _t(
    '本快照没有关联到该文献的测量行。文献仍完整保留。',
    'This snapshot has no measurement linked to this reference. The record is still complete.',
  );
  String get referenceGroupsHint => _t(
    '按所测系列分组；组内记录数来自当前快照。',
    'Grouped by measured series; counts come from this snapshot.',
  );
  String get referenceGroupCount => _t('条记录', 'records');
  String get referenceShowMeasurements =>
      _t('查看该组测量', 'Show measurements in this group');
  String get referenceCopyCitation =>
      _t('复制书目信息', 'Copy bibliographic information');
  String get referenceDuplicateDoi => _t(
    '同一 DOI/INSPIRE 下的独立记录',
    'Independent records sharing this DOI/INSPIRE identifier',
  );
  String get referenceRaw => _t('原始文献行', 'Raw reference row');
  String get referenceMissingField =>
      _t('快照未提供该字段', 'Field not present in this snapshot');

  String get favoritesTitle => _t('收藏', 'Favorites');
  String get favoritesEmptyFilter =>
      _t('当前筛选下没有收藏。', 'No favorites match the current filter.');
  String get favoritesEmpty => _t(
    '还没有收藏。可在粒子、条目、衰变或文献页添加。',
    'No favorites yet. Add one from a particle, entry, decay or reference page.',
  );
  String get favoritesAdd => _t('收藏', 'Add to favorites');
  String get favoritesRemove => _t('取消收藏', 'Remove from favorites');
  String get favoritesAdded => _t('已加入收藏', 'Added to favorites');
  String get favoritesRemoved => _t('已取消收藏', 'Removed from favorites');
  String get favoritesUndo => _t('撤销', 'Undo');
  String get favoritesAll => _t('全部', 'All');
  String get favoritesEntries => _t('条目', 'Entries');
  String get favoritesReferences => _t('文献', 'References');
  String get favoritesNeedsReselect => _t(
    '该收藏在当前快照中无法唯一解析，请重新选择。',
    'This favorite cannot be resolved uniquely in the current snapshot; please reselect.',
  );
  String get favoritesCount => _t('项收藏', 'favorites');

  String get notesTitle => _t('笔记', 'Notes');
  String get notesNew => _t('新建笔记', 'New note');
  String get notesNewCollection => _t('新建 collection', 'New collection');
  String get notesCollectionName => _t('collection 名称', 'Collection name');
  String get notesCollectionFailed =>
      _t('无法创建 collection', 'Could not create collection');
  String get notesAllCollections => _t('全部笔记', 'All notes');
  String get notesCollections => _t('Collections', 'Collections');
  String get notesPdgLookup => _t('PDG 速查', 'PDG lookup');
  String get notesPdgLookupHint =>
      _t('搜索粒子、性质或文献题名', 'Search particles, properties or titles');
  String get notesPdgLookupHintDetail => _t(
    '点击结果会打开对应页面；在页面中可用笔记按钮把来源加入笔记。',
    'Clicking a result opens its page; use the page\'s note button to add it to a note.',
  );
  String get notesPdgLookupIdle =>
      _t('输入名称或题名开始速查。', 'Type a name or title to start.');
  String get notesPdgLookupEmpty =>
      _t('没有匹配的 PDG 条目。', 'No matching PDG entries.');
  String get notesPdgLookupFailed => _t('速查失败', 'Lookup failed');
  String get notesPdgLookupAdded => _t('来源已添加到笔记', 'Source added to note');
  String notesSourceLine(String source) => _t('来源：$source', 'Source: $source');
  String get notesAddToCollection => _t('添加到 Collection', 'Add to collection');
  String get notesAlreadyInCollection => _t('已在其中', 'Already added');
  String get notesNoCollections =>
      _t('还没有 Collection；先新建一个。', 'No collections yet; create one first.');
  String get notesCollectionEmpty =>
      _t('此 collection 还没有笔记。', 'No notes in this collection yet.');
  String get notesEdit => _t('编辑笔记', 'Edit note');
  String get notesLocalOnly => _t('仅保存在本机', 'Stored on this device only');
  String get notesSearchHint => _t('搜索标题或正文…', 'Search titles or body…');
  String get notesSearchClear => _t('清除搜索', 'Clear search');
  String get notesEmpty => _t(
    '还没有笔记。可以在粒子、性质或文献页添加，或在这里新建一条。',
    'No notes yet. Add one from a particle, property/series or reference page, or create one here.',
  );
  String get notesNoSearchResults =>
      _t('没有匹配的笔记。', 'No notes match this search.');
  String get notesLoadFailed => _t('读取笔记失败', 'Could not load notes');
  String get notesSearchFailed => _t('搜索笔记失败', 'Could not search notes');
  String get notesUnavailable => _t(
    '笔记数据库不可用；粒子数据仍可正常查询。',
    'The notes database is unavailable; particle data still works.',
  );
  String get notesUnavailableHint => _t(
    '笔记保存在独立的本地数据库中；打不开笔记不会影响 PDG 查询。重启应用后会再次尝试。',
    'Notes live in a separate local database. A notes failure never blocks PDG lookups; the app retries on the next launch.',
  );
  String get notesUntitled => _t('无标题笔记', 'Untitled note');
  String get notesSelectPrompt =>
      _t('选择一条笔记查看或编辑，或新建一条。', 'Select a note to view or edit, or create one.');
  String get notesTitleHint => _t('标题', 'Title');
  String get notesBodyHint => _t('用 Markdown 记录…', 'Write in Markdown…');
  String get notesPreview => _t('预览', 'Preview');
  String get notesWrite => _t('编辑', 'Write');
  String get notesPreviewHint => _t(
    '边写边预览 Markdown；宽屏时编辑与预览并排。',
    'Preview Markdown while writing; on wide screens editor and preview sit side by side.',
  );
  String get notesTagsManage => _t('标签管理', 'Manage tags');
  String get notesTagsManagerHint => _t(
    '重命名或删除标签会同步到所有笔记；笔记本身不会被删除。',
    'Renaming or deleting a tag updates every note; the notes themselves are kept.',
  );
  String get notesTagsEmpty => _t('还没有标签。', 'No tags yet.');
  String get notesTagsRename => _t('重命名标签', 'Rename tag');
  String get notesTagsDelete => _t('删除标签', 'Delete tag');
  String notesTagsDeleteConfirm(String tag, int count) => _t(
    '从 $count 篇笔记中删除标签“$tag”？笔记本身会保留。',
    'Remove the tag "$tag" from $count notes? The notes themselves are kept.',
  );
  String notesTagsRenamed(String from, String to, int count) => _t(
    '已将“$from”重命名为“$to”（$count 篇笔记）。',
    'Renamed "$from" to "$to" in $count notes.',
  );
  String notesTagsDeleted(String tag) =>
      _t('已删除标签“$tag”。', 'Deleted tag "$tag".');
  String notesTagsFor(String tag) => _t('标签：$tag', 'Tag: $tag');
  String get notesTagsNoNotes => _t('没有带这个标签的笔记。', 'No notes with this tag.');
  String get notesTagsHint => _t(
    '标签，如 #lifetime #D0，也可用逗号分隔',
    'Tags, e.g. #lifetime #D0, or comma separated',
  );
  String get notesTagsLabel => _t('标签', 'Tags');
  String get notesRemoveAnchor => _t('移除关联', 'Remove link');
  String get notesAnchorRemoved => _t('已移除关联', 'Link removed');
  String get notesAnchorsLabel => _t('关联条目', 'Anchors');
  String get notesAnchorUnresolved => _t('锚点尚未解析', 'Anchor not resolved');
  String get notesDraft => _t('草稿', 'Draft');
  String get notesSavePending => _t('待保存', 'Unsaved changes');
  String get notesSaving => _t('保存中…', 'Saving…');
  String get notesSaved => _t('已保存', 'Saved');
  String get notesSaveFailed => _t('保存失败', 'Save failed');
  String get notesSaveRetry => _t('重试保存', 'Retry save');
  String get notesReload => _t('重新载入', 'Reload');
  String get notesKeepMine => _t('保留我的版本', 'Keep mine');
  String get notesKeepMineTitle =>
      _t('覆盖对方的修改？', 'Overwrite the other version?');
  String get notesKeepMineBody => _t(
    '这会用当前编辑内容覆盖其他编辑器刚保存的版本。只有确认对方的内容可以丢弃时才继续。',
    'This overwrites the version just saved by another editor. Continue only if the other changes can be discarded.',
  );
  String get notesReloadTitle => _t('重新载入笔记？', 'Reload note?');
  String get notesReloadBody => _t(
    '笔记已被其他编辑器更新。重新载入会丢弃当前未保存的修改。',
    'This note was updated elsewhere. Reloading discards the unsaved local changes.',
  );
  String get notesDelete => _t('删除笔记', 'Delete note');
  String get notesDeleteConfirmTitle => _t('删除这条笔记？', 'Delete this note?');
  String get notesDeleteConfirmBody => _t(
    '笔记将从列表和关联页面移除；应用内无法撤销。',
    'The note disappears from the list and its linked pages. This cannot be undone in the app.',
  );
  String get notesDeleteConfirm => _t('删除', 'Delete');
  String get notesDeleted => _t('笔记已删除', 'Note deleted');
  String get notesUndo => _t('撤销', 'Undo');
  String get notesTrash => _t('回收站', 'Trash');
  String get notesLoadMore => _t('加载更多', 'Load more');
  String get notesTrashEmpty => _t('回收站是空的。', 'Trash is empty.');
  String get notesRestore => _t('恢复', 'Restore');
  String get notesRestored => _t('笔记已恢复', 'Note restored');
  String get notesDeleteFailed => _t('删除失败', 'Could not delete the note');
  String get notesCopyMarkdown => _t('复制为 Markdown', 'Copy as Markdown');
  String get notesCaptureTitle => _t('添加到笔记', 'Add to note');
  String get notesCaptureNew => _t('新建笔记', 'New note');
  String get notesCaptureSearchHint => _t('搜索已有笔记', 'Search existing notes');
  String get notesCaptureAppendHint => _t(
    '选择已有笔记追加选中的内容，或新建一条：',
    'Append the selection to an existing note, or create one:',
  );
  String get notesAddSelection => _t('添加到笔记', 'Add to note');
  String get navHome => _t('主页', 'Home');
  String get notesCopiedMarkdown => _t('Markdown 已复制', 'Markdown copied');
  String get notesExportJsonFile => _t('导出 JSON 文件…', 'Export JSON file…');
  String get notesExportMarkdownFile =>
      _t('导出 Markdown 文件…', 'Export Markdown file…');
  String get notesImportJsonFile =>
      _t('从 JSON 文件导入…', 'Import from JSON file…');
  String get notesExportFileDone => _t('笔记已导出', 'Notes exported');
  String get notesExportFileFailed => _t('导出失败', 'Export failed');
  String get notesImportDone => _t('导入完成', 'Import complete');
  String notesImportSummary(int added, int skipped, int failed) => _t(
    '新增 $added 条，跳过 $skipped 条，失败 $failed 条',
    'Added $added, skipped $skipped, failed $failed',
  );
  String get notesImportFailed => _t('导入失败', 'Import failed');
  String get notesExportAll => _t('导出全部笔记（JSON）', 'Export all notes (JSON)');
  String get notesExportAllDone =>
      _t('全部笔记已复制为 JSON', 'All notes copied as JSON');
  String get notesExportEmpty => _t('没有可导出的笔记。', 'No notes to export.');
  String get notesAdd => _t('添加笔记', 'Add note');
  String get notesAddSummary => _t('把汇总值加入笔记', 'Add summary value to note');
  String get notesAddToTarget => _t('为本条目添加笔记', 'Add a note about this entry');
  String get notesRecent => _t('最近笔记', 'Recent notes');
  String get notesEmptyForTarget =>
      _t('该条目还没有笔记。', 'No notes for this entry yet.');
  String get notesOpenNote => _t('打开笔记', 'Open note');
  String get notesBacklinksTitle => _t('全部关联笔记', 'All linked notes');
  String get notesLinkNote => _t('链接到另一条笔记', 'Link to another note');
  String get notesRelated => _t('相关笔记', 'Related notes');
  String get notesRelatedEmpty =>
      _t('没有其他共享条目的笔记。', 'No other notes share an entity.');
  String get notesRelatedTitle => _t('相关笔记', 'Related notes');
  String get notesMeasurementAdd => _t('把测量值加入笔记', 'Add value to note');
  String get notesMentionedTitle => _t('正文中链接到此处', 'Linked in text');
  String get notesMentionedEmpty => _t('还没有正文链接。', 'No textual links yet.');
  String get notesViewAll => _t('全部笔记', 'All notes');
  String notesCount(int count) =>
      _t('$count 条笔记', count == 1 ? '1 note' : '$count notes');
  String get notesJustNow => _t('刚刚', 'just now');
  String notesMinutesAgo(int minutes) => _t('$minutes 分钟前', '$minutes min ago');
  String notesHoursAgo(int hours) => _t('$hours 小时前', '$hours h ago');
  String get notesYesterday => _t('昨天', 'yesterday');
  String notesUpdated(String time) => _t('更新于 $time', 'Updated $time');

  String get settingsTitle => _t('设置', 'Settings');
  String get helpTitle => _t('使用说明与名词解释', 'Help and glossary');
  String get helpSubtitle =>
      _t('软件功能、数据含义和常用术语', 'Features, data semantics, and common terms');
  String get settingsHelp => _t('使用说明', 'Help');
  String get reviewsTitle => _t('PDG 综述', 'PDG reviews');
  String get reviewsSubtitle =>
      _t('PDG 2026 官方综述目录', 'Official PDG 2026 review directory');
  String get reviewsIntro => _t(
    '综述正文来自 PDG 官方 PDF：可逐篇下载缓存，也可缓存全部（约 106 MB）；缓存后可直接在应用内阅读。未缓存时需要联网下载，核心粒子查询始终可离线使用。',
    'Review texts come from official PDG PDFs. Download individual reviews or cache all of them (about 106 MB); cached copies open in the app. Uncached reviews need the network, while core particle lookups stay offline.',
  );
  String get reviewsSearchHint =>
      _t('搜索综述标题或分类', 'Search review titles or categories');
  String get reviewsEmpty => _t('没有匹配的综述。', 'No matching reviews.');
  String get reviewHighlight => _t('高亮所选文字', 'Highlight selection');
  String get reviewHighlightModeOn => _t(
    '高亮模式已开启：选中文字会自动高亮',
    'Highlight mode on: selecting text highlights it',
  );
  String get reviewPdfLoading => _t('PDF 正在加载…', 'PDF is loading…');
  String get reviewDeleteConfirm => _t(
    '删除这条高亮及其笔记？笔记会进入回收站。',
    'Delete this highlight and its note? The note goes to the recycle bin.',
  );
  String get reviewSelectText =>
      _t('请先在 PDF 中选择文字。', 'Select text in the PDF first.');
  String get reviewAnnotations => _t('批注', 'Annotations');
  String get reviewAnnotationEmpty => _t(
    '选中 PDF 文字后点击高亮按钮，批注会显示在这里。',
    'Select PDF text and use the highlight button; annotations appear here.',
  );
  String get reviewHighlightColor => _t('高亮颜色', 'Highlight color');
  String get reviewAdjustRange => _t('调整高亮范围', 'Adjust highlight range');
  String get reviewAdjustRangeHint => _t(
    '拖动两个圆形把手调整起止位置，然后点右上角勾保存。',
    'Drag the two round handles to adjust the start and end, then tap the check button to save.',
  );
  String get reviewSaveRange => _t('保存高亮范围', 'Save highlight range');
  String reviewHighlightColorName(String color) => switch (color) {
    'green' => _t('绿色', 'Green'),
    'pink' => _t('粉色', 'Pink'),
    'blue' => _t('蓝色', 'Blue'),
    _ => _t('黄色', 'Yellow'),
  };
  String get reviewAnnotationSidebar => _t('批注侧栏', 'Annotation sidebar');
  String get reviewAnnotationNote => _t('批注备注', 'Annotation note');
  String get reviewAnnotationNoteHint => _t('可选，写一句提醒…', 'Optional note…');
  String reviewAnnotationPage(int page) => _t('第 $page 页', 'Page $page');
  String get reviewAnnotationEdit => _t('编辑备注', 'Edit note');
  String get reviewOpenNote => _t('打开笔记', 'Open note');
  String get reviewNotCached => _t(
    '该综述尚未缓存，请先在「PDG 综述」中下载。',
    'This review is not cached; download it in PDG reviews.',
  );
  String get reviewOpenOfficial => _t('打开官方 PDF', 'Open official PDF');
  String get reviewsOpenFailed =>
      _t('无法打开综述链接。', 'Could not open the review link.');
  String get reviewsCacheAll => _t('缓存全部未下载', 'Cache all uncached');
  String get reviewsStop => _t('停止', 'Stop');
  String get reviewsClearCache => _t('清除缓存', 'Clear cache');
  String get reviewsManageCache => _t('管理缓存', 'Manage cache');
  String get reviewsSelectAll => _t('全选', 'Select all');
  String get reviewsSelectNone => _t('全不选', 'Select none');
  String get reviewsCacheSelectHint =>
      _t('选择要删除的综述 PDF。', 'Select cached review PDFs to delete.');
  String reviewsDeleteSelected(int count) =>
      _t('删除所选（$count）', 'Delete selected ($count)');
  String reviewsCacheRemoved(int count) =>
      _t('已删除 $count 篇综述缓存。', 'Removed $count cached reviews.');
  String get reviewsCached => _t('已缓存', 'Cached');
  String get reviewsFilterAll => _t('全部', 'All');
  String get reviewsFilterCached => _t('已缓存', 'Cached');
  String get reviewsFilterNotCached => _t('未缓存', 'Not cached');
  String get reviewsDownload => _t('下载并缓存', 'Download and cache');
  String get reviewsDownloadFailed => _t('综述下载失败。', 'Review download failed.');
  String get reviewsCacheAllDone =>
      _t('全部可下载综述已处理。', 'All downloadable reviews processed.');
  String get reviewsClearCacheConfirm =>
      _t('清除本机缓存的 PDG 综述 PDF？', 'Clear cached PDG review PDFs on this device?');
  String get reviewsCacheCleared => _t('综述缓存已清除。', 'Review cache cleared.');
  String reviewsCacheStatus(int cached, int total, String size) =>
      _t('已缓存 $cached/$total · $size', 'Cached $cached/$total · $size');
  String reviewsBulkProgress(int done, int total) =>
      _t('缓存中 $done/$total', 'Caching $done/$total');
  String get settingsAppearance => _t('外观', 'Appearance');
  String get settingsTheme => _t('主题', 'Theme');
  String get settingsThemeSystem => _t('随系统', 'System');
  String get settingsThemeLight => _t('浅色', 'Light');
  String get settingsThemeDark => _t('深色', 'Dark');
  String get settingsLanguage => _t('界面语言', 'Language');
  String get settingsLanguageSystem => _t('随系统', 'System');
  String get settingsLanguageZh => _t('中文', '中文');
  String get settingsLanguageEn => _t('English', 'English');
  String get settingsTextSize => _t('字体大小', 'Text size');
  String get settingsDetailedMode => _t('详细模式', 'Detailed mode');
  String get settingsDetailedModeHint => _t(
    '显示原始字段、flags、内部行号和快照哈希。关闭后为简约版，只保留性质、测量、衰变和文献。',
    'Show raw fields, flags, internal row IDs and the snapshot hash. Turn off for a simpler view focused on properties, measurements, decays and references.',
  );
  String get settingsSidebarMode => _t('桌面侧边栏', 'Desktop sidebar');
  String get settingsSidebarAuto => _t('自动', 'Auto');
  String get settingsSidebarAlways => _t('始终显示', 'Always');
  String get settingsSidebarOff => _t('关闭', 'Off');
  String get settingsNoteLinkMode => _t('笔记内链接', 'Links inside notes');
  String get settingsNoteLinkPage => _t('直接打开页面', 'Open page');
  String get settingsNoteLinkSidebar =>
      _t('在笔记侧栏预览', 'Preview in note sidebar');
  String get settingsNoteLinkHint => _t(
    '选择点击笔记正文里的 PDG/文献链接时，是直接跳转还是先在侧栏预览。',
    'Choose whether a PDG or reference link in note text opens the page directly or previews in the note sidebar.',
  );

  String get settingsShortcuts => _t('键盘快捷键', 'Keyboard shortcuts');
  String get settingsShortcutsHint => _t(
    '点击组合键可重新录制；发生冲突时会提示。默认值保留原有键位。',
    'Click a combination to record a new one. Conflicts are rejected. Defaults keep the original shortcuts.',
  );
  String get settingsShortcutChange => _t('修改', 'Change');
  String get settingsShortcutReset => _t('恢复默认', 'Reset');
  String get settingsShortcutResetAll => _t('全部恢复默认', 'Reset all');
  String get settingsShortcutNotSet => _t('未设置', 'Not set');
  String get settingsShortcutRecorderTitle => _t('录制快捷键', 'Record shortcut');
  String get settingsShortcutRecorderHint => _t(
    '按下新的组合键；需要至少一个修饰键。Esc 取消。',
    'Press a new key combination. At least one modifier is required; Esc cancels.',
  );
  String get settingsShortcutNeedsModifier =>
      _t('请使用至少一个修饰键。', 'Use at least one modifier key.');
  String settingsShortcutConflict(String command) => _t(
    '该组合键已被“$command”使用。',
    'That combination is already used by “$command”.',
  );
  String get settingsShortcutClear => _t('清除', 'Clear');
  String get settingsShortcutSaved => _t('快捷键已更新。', 'Shortcut updated.');

  String shortcutCommandLabel(AppShortcutCommand command) => switch (command) {
    AppShortcutCommand.search => _t('搜索', 'Search'),
    AppShortcutCommand.favorites => _t('收藏', 'Favorites'),
    AppShortcutCommand.notes => _t('笔记', 'Notes'),
    AppShortcutCommand.settings => _t('设置', 'Settings'),
    AppShortcutCommand.newNote => _t('新建笔记', 'New note'),
    AppShortcutCommand.back => _t('后退', 'Back'),
    AppShortcutCommand.forward => _t('前进', 'Forward'),
  };

  String get notesLinkPreview => _t('链接预览', 'Link preview');
  String get notesOpenPage => _t('打开完整页面', 'Open full page');
  String get notesLinkMissing =>
      _t('无法解析这个链接。', 'This link could not be resolved.');
  String get notesLinkLoading => _t('正在读取…', 'Loading…');
  String get settingsSidebarHint => _t(
    '自动：≥620 px 显示；始终显示：≥480 px 保留侧栏；关闭：不显示侧栏。',
    'Auto: show at ≥620 px; Always: keep it at ≥480 px; Off: hide it.',
  );
  String get settingsTextSizeHint => _t(
    '系统字体缩放始终优先于本设置。',
    'System text scaling always applies on top of this setting.',
  );
  String get settingsZoteroCache => _t('Zotero 条目缓存', 'Zotero item cache');
  String get settingsZotero => _t('Zotero 集成', 'Zotero integration');
  String get settingsZoteroEnabled =>
      _t('启用 Zotero 集成', 'Enable Zotero integration');
  String get settingsZoteroEnabledHint => _t(
    '关闭后不探测 Zotero、不显示 Zotero 按钮，也不更新索引。复制 BibTeX 不受影响。',
    'When off, Zotero is not probed, Zotero buttons are hidden, and the index is not updated. Copying BibTeX still works.',
  );
  String get settingsZoteroAddAvailable =>
      _t('zotero-inspire：添加功能可用', 'zotero-inspire: add available');
  String settingsZoteroAddAvailableVersion(String version) => _t(
    'zotero-inspire $version：添加功能可用',
    'zotero-inspire $version: add available',
  );
  String settingsZoteroAddTooOld(String version) => _t(
    'zotero-inspire $version 版本过低，需要 4.1.0+',
    'zotero-inspire $version is too old; 4.1.0+ is required',
  );
  String get settingsZoteroPluginMissing => _t(
    '未检测到可用的 zotero-inspire（需要 4.1.0+）',
    'No usable zotero-inspire detected (4.1.0+ required)',
  );
  String get settingsZoteroNotRunning => _t(
    'Zotero 未运行；启动 Zotero 后可使用 zotero-inspire',
    'Zotero is not running; start it to use zotero-inspire',
  );
  String get settingsZoteroInstallUpdate =>
      _t('安装/更新插件', 'Install/update plugin');
  String get zoteroInspireSetupTitle =>
      _t('需要 zotero-inspire 4.1.0', 'zotero-inspire 4.1.0 required');
  String get zoteroInspireSetupMissing => _t(
    '已检测到 Zotero，但没有检测到可用的 zotero-inspire 插件。安装 4.1.0 或更高版本后，才能从 Particle Library 直接把条目添加到 Zotero。',
    'Zotero was detected, but no usable zotero-inspire plugin was found. Install 4.1.0 or newer to add items from Particle Library directly.',
  );
  String zoteroInspireSetupTooOld(String version) => _t(
    'zotero-inspire 版本过低（当前 $version）。请更新到 4.1.0 或更高版本后再试。',
    'zotero-inspire is too old (current $version). Update to 4.1.0 or newer and try again.',
  );
  String get zoteroInspireSetupNotRunning =>
      _t('Zotero 当前未运行；请先启动 Zotero。', 'Zotero is not running; start it first.');
  String get zoteroInspireSetupHint => _t(
    '安装或更新插件后不需要重启 Particle Library；重新点击 Zotero 按钮即可。',
    'You do not need to restart Particle Library after installing or updating the plugin; click the Zotero button again.',
  );
  String get zoteroInspireOpenRelease =>
      _t('打开安装/更新页面', 'Open install/update page');
  String get zoteroInspireCopyBibtex => _t('复制 BibTeX', 'Copy BibTeX');
  String get settingsZoteroCacheEmpty => _t(
    '尚未构建。可在此手动构建；开启自动更新时，Zotero 运行时会在启动时构建。',
    'Not built yet. Build it here, or let automatic update build it at startup when Zotero is running.',
  );
  String settingsZoteroCacheStatus(int count, String builtAt) => _t(
    '已索引 $count 条 · 构建于 $builtAt',
    '$count items indexed · built $builtAt',
  );
  String get settingsZoteroCacheStale => _t(
    '索引已超过 24 小时，建议更新。',
    'The index is older than 24 hours; an update is recommended.',
  );
  String get settingsZoteroCacheBuild => _t('构建缓存', 'Build cache');
  String get settingsZoteroCacheUpdate => _t('更新缓存', 'Update cache');
  String get settingsZoteroCacheClear => _t('清除缓存', 'Clear cache');
  String get settingsZoteroCacheAutoUpdate =>
      _t('自动更新 Zotero 索引', 'Update Zotero index automatically');
  String get settingsZoteroCacheAutoUpdateHint => _t(
    '启动时检查；索引缺失或超过 24 小时才构建/更新。缓存只影响匹配速度和筛选，不影响 Zotero 联动。',
    'Checked at startup; builds or refreshes the index only when it is missing or older than 24 hours. The cache affects matching speed and filters, not Zotero actions.',
  );
  String get settingsZoteroCacheHint => _t(
    '缓存只读取 Zotero 本地 API，不修改 Zotero。',
    'The cache only reads the local Zotero API and never changes Zotero.',
  );
  String settingsZoteroCacheBuilding(int fetched, int total) => total > 0
      ? _t('正在读取 Zotero：$fetched / $total', 'Reading Zotero: $fetched / $total')
      : _t('正在读取 Zotero：$fetched 条', 'Reading Zotero: $fetched items');
  String get settingsZoteroCacheDone =>
      _t('Zotero 缓存已更新。', 'Zotero cache updated.');
  String get settingsZoteroCacheFailed =>
      _t('Zotero 缓存构建失败', 'Zotero cache build failed');
  String get settingsData => _t('数据与快照', 'Data and snapshot');
  String get settingsStorage => _t('本机存储', 'Local storage');
  String get settingsClearRecents => _t('清除最近查询', 'Clear recent searches');
  String get settingsClearRecentsConfirm => _t(
    '清除全部最近查询？收藏不受影响。',
    'Clear all recent searches? Favorites are not affected.',
  );
  String get settingsClearRecentsDone =>
      _t('最近查询已清除', 'Recent searches cleared');
  String get settingsAbout => _t('关于与覆盖范围', 'About and coverage');
  String get settingsAboutText => _t(
    'Particle Library 是离线 PDG 数据查阅工具，不是 PDG 官方应用。数据来自随包 pdgall 快照，按 CC BY 4.0 使用并保留来源。',
    '$kAppName is an offline PDG data browser, not an official PDG application. Data comes from the bundled pdgall snapshot under CC BY 4.0; attribution is retained.',
  );
  String get settingsLicenses =>
      _t('应用与第三方许可证', 'App and third-party licenses');
  String get settingsSourceCode => _t('源代码（MPL-2.0）', 'Source code (MPL-2.0)');
  String get settingsInspireDisclaimer => _t(
    'INSPIRE 是外部文献服务；本应用不代表 INSPIRE 或 CERN。',
    'INSPIRE is an external literature service; this app is not affiliated with INSPIRE or CERN.',
  );
  String get settingsCheckUpdates => _t('检查更新', 'Check for updates');
  String get settingsUpdateAppStore => _t(
    'iOS 版本通过 App Store 更新。',
    'Updates for iOS are delivered by the App Store.',
  );
  String get settingsOpenAppStore => _t('打开 App Store', 'Open the App Store');
  String get settingsCheckingUpdates => _t('正在检查更新…', 'Checking for updates…');
  String get settingsUpdateCurrent => _t('已是最新版本。', 'You are up to date.');
  String get settingsUpdateUnavailable => _t(
    '暂时无法检查更新。请稍后重试，或从发布页面手动下载。',
    'Update check is unavailable. Try again later or download from the releases page.',
  );
  String get updateLater => _t('稍后', 'Later');
  String get updateOpen => _t('打开下载页面', 'Open download page');
  String get updateAvailableMessage => _t(
    '有新版本可用。建议下载并安装最新版本。',
    'A newer version is available. Download and install the latest release.',
  );
  String updateAvailableTitle(String version) =>
      _t('发现新版本 $version', 'Version $version is available');
  String get settingsBuiltBy => _t(
    '由郭奉坤 (ITP, CAS) 使用 DeepSeek Harness 构建。',
    'Built by Feng-Kun Guo (ITP, CAS) with DeepSeek Harness.',
  );
  String get settingsCoverageText => _t(
    '本版本完整读取条目、性质、衰变参与项、全部测量列、脚注、文献与历史汇总；结构语义只在能由原文确定时展示，无法唯一确定的片段保留原文。',
    'This build reads entries, properties, decay tokens, all measurement columns, footnotes, references and historical summaries. Structural semantics are shown only where the source supports them; unresolved fragments stay visible and are marked.',
  );
  String get settingsLinks => _t('官方来源', 'Official sources');
  String get settingsPdgApi =>
      _t('PDG API 与数据库说明', 'PDG API and database documentation');
  String get settingsLicenseLink =>
      _t('数据许可（CC BY 4.0）', 'Data license (CC BY 4.0)');
  String get settingsAppVersion => _t('应用版本', 'App version');
  String settingsVersionValue(String version) =>
      _t('版本 $version', 'Version $version');
  String get settingsSnapshotVersion => _t('快照版本', 'Snapshot version');
  String get settingsSnapshotFile => _t('快照文件', 'Snapshot file');
  String get settingsSchema => _t('schema', 'schema');
  String get settingsRelease => _t('发布标记', 'release');
  String get settingsHash => _t('SHA-256', 'SHA-256');
  String get settingsRows => _t('行数', 'rows');
  String get settingsTableStats => _t('快照表统计', 'Snapshot table statistics');
  String get settingsShowStats =>
      _t('查看全部表行数', 'Show row counts for all tables');
  String get codeTableTitle =>
      _t('编码说明（pdgdoc 原表）', 'Code interpretations (raw pdgdoc)');
  String get codeTableHint => _t(
    '快照自带的官方编码解释；未知编码不做猜测。',
    'The snapshot’s official code interpretations; unknown codes are not guessed.',
  );
  String get settingsNoDescription => _t('尚无说明。', 'No description.');
  String get settingsCopyHash => _t('复制哈希', 'Copy hash');
  String get settingsCopyCitation => _t('复制引用', 'Copy citation');
  String get settingsNotesBackup => _t('备份笔记数据库', 'Back up notes database');
  String get settingsFullBackup => _t('完整备份', 'Full backup');
  String get settingsFullBackupExport => _t('导出完整备份…', 'Export full backup…');
  String get settingsFullBackupImport => _t('导入完整备份…', 'Import full backup…');
  String get settingsFullBackupHint => _t(
    '包含设置、收藏、笔记、高亮 anchor 和已缓存的综述 PDF，导出为 ZIP；导入时自动识别并合并笔记，不删除现有数据。',
    'Includes settings, favorites, notes, highlight anchors and cached review PDFs as a ZIP. Import detects the format and merges notes without deleting current data.',
  );
  String get settingsFullBackupConfirm => _t(
    '导入会恢复备份中的设置和收藏，并合并笔记与 PDF 缓存；现有笔记不会被删除。继续？',
    'Import restores settings and favorites from the backup, and merges notes and cached PDFs. Existing notes are not deleted. Continue?',
  );
  String get settingsFullBackupDone => _t('完整备份已导出', 'Full backup exported');
  String get settingsFullBackupImported =>
      _t('完整备份已导入', 'Full backup imported');
  String get settingsFullBackupFailed =>
      _t('完整备份操作失败', 'Full backup operation failed');
  String settingsFullBackupSummary(int notes, int pdfs) =>
      _t('$notes 条笔记，$pdfs 个 PDF', '$notes notes, $pdfs PDFs');
  String get settingsNotesBackupDone => _t('笔记备份已创建', 'Notes backup created');
  String get settingsNotesBackupFailed => _t('笔记备份失败', 'Notes backup failed');
  String get settingsNotesBackupHint => _t(
    '备份保存在应用数据目录的 backups 文件夹，自动保留最近 5 份。',
    'Backups are kept in the application data backups folder; the latest five are retained.',
  );
  String get settingsStorageHint => _t(
    '原始快照只读；收藏、最近查询、笔记与设置保存在独立的本机文件中。',
    'The raw snapshot is read-only; favorites, recent searches, notes and settings live in separate local files.',
  );

  String get metadataValueType => _t('汇总类型', 'Summary type');
  String get metadataInSummaryTable => _t('Summary Table', 'Summary Table');
  String get metadataLimitType => _t('结果类型', 'Result type');
  String get metadataEdition => _t('版次', 'Edition');
  String get metadataId => _t('数据库行号', 'Row ID');
  String get metadataSnapshots => _t('快照与版本', 'Snapshot and versions');

  String reasonLabel(String reason) {
    return switch (reason) {
      'exactPdgid' => _t('精确 PDG 标识符', 'Exact PDG identifier'),
      'exactName' => _t('精确名称', 'Exact name'),
      'commonAlias' => _t('常用别名', 'Common alias'),
      'namePrefix' => _t('名称前缀', 'Name prefix'),
      'nameContains' => _t('名称包含', 'Name contains'),
      'mcNumber' => _t('MC 编号', 'MC number'),
      'titleMatch' => _t('标题命中', 'Title match'),
      'textMatch' => _t('说明文本命中', 'Section-text match'),
      'decayText' => _t('衰变原文命中', 'Decay-text match'),
      'referenceIdentifier' => _t('文献标识符', 'Reference identifier'),
      'referenceTitle' => _t('文献题目', 'Reference title'),
      _ => reason,
    };
  }

  String entryCount(int count) => _t('$count 个条目', '$count entries');
  String itemCount(int count) => _t('$count 项', '$count items');
  String referenceCount(int count) => _t('$count 篇文献', '$count references');
  String measurementCount(int count) => _t('$count 条测量', '$count measurements');
  String modeCount(int count) => _t('$count 个模式', '$count modes');
  String propertyCount(int count) => _t('$count 个性质', '$count properties');
  String particleMoreProperties(int remaining) =>
      _t('显示更多性质（剩余 $remaining）', 'Show more properties ($remaining left)');
  String candidateCount(int count) => _t('$count 个候选', '$count candidates');
  String versionLine(String edition, String schema) =>
      _t('PDG $edition · schema $schema', 'PDG $edition · schema $schema');
  String showingMeasurements(int loaded, int total) =>
      _t('已显示 $loaded / $total 条', '$loaded of $total shown');
  String warningPrefix() => _t('注意：', 'Note: ');
}

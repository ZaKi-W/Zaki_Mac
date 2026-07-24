export const ZHIHU_READING_CSS = `
  .AppHeader,
  .QuestionHeader-side,
  .Question-sideColumn,
  .GlobalSideBar,
  .TopstoryPageHeader,
  .CornerButtons,
  .QuestionRelatedReadings,
  .RelatedReadings,
  .Recommendations-Main,
  .WriteArea,
  .TopstoryItem--advertCard,
  .Pc-feedAd,
  [data-za-detail-view-path-module="RightSideBar"],
  [data-za-detail-view-name="Ads"] {
    display: none !important;
  }

  .App-main,
  .Question-main,
  .Topstory-container,
  .Search-container,
  .Profile-main {
    width: 100% !important;
    max-width: 940px !important;
    margin-inline: auto !important;
    padding-top: 14px !important;
  }

  .QuestionHeader-content,
  .QuestionHeader-footer-inner,
  .Question-mainColumn,
  .Topstory-mainColumn,
  .SearchMain,
  .List,
  .ColumnPage-main {
    width: 100% !important;
    max-width: 840px !important;
    margin-inline: auto !important;
    float: none !important;
  }

  .RichContent img,
  .RichContent picture,
  .RichContent video,
  .RichText img {
    visibility: visible !important;
    opacity: 1 !important;
    filter: none !important;
  }
`

export const ZHIHU_DARK_CSS = `
  :root {
    color-scheme: dark !important;
    --assistant-bg: #181a1e;
    --assistant-surface: #23262c;
    --assistant-raised: #2b2f36;
    --assistant-border: #393e47;
    --assistant-text: #f0f1f2;
    --assistant-muted: #a2a8b2;
  }

  html,
  body,
  #root,
  .App-main,
  .Question-main,
  .QuestionHeader,
  .Search-container,
  .Profile-main {
    background: var(--assistant-bg) !important;
    color: var(--assistant-text) !important;
  }

  .AppHeader,
  .Sticky,
  .Card,
  .Modal-inner,
  .Popover-content,
  .Menu,
  .QuestionHeader-content,
  .QuestionHeader-footer,
  .TopstoryItem,
  .ContentItem,
  .AnswerItem,
  .Comments-container,
  .CommentListV2,
  .CommentItemV2,
  .SearchResult-Card,
  .List-item {
    background-color: var(--assistant-surface) !important;
    color: var(--assistant-text) !important;
    border-color: var(--assistant-border) !important;
    box-shadow: none !important;
  }

  body,
  .RichText,
  .RichContent-inner,
  .QuestionHeader-title,
  .ContentItem-title,
  .CommentItemV2-content {
    color: var(--assistant-text) !important;
  }

  .ContentItem-meta,
  .AuthorInfo-detail,
  .CommentItemV2-time,
  .CommentItemV2-footer,
  .Tabs-link,
  .Button--plain {
    color: var(--assistant-muted) !important;
  }

  input,
  textarea,
  select,
  .Input-wrapper,
  .SearchBar-input,
  [contenteditable="true"] {
    background-color: var(--assistant-raised) !important;
    color: var(--assistant-text) !important;
    border-color: var(--assistant-border) !important;
  }

  .VoteButton,
  .Button:not(.Button--primary) {
    background: var(--assistant-raised) !important;
    color: var(--assistant-text) !important;
    border-color: var(--assistant-border) !important;
  }

  ${ZHIHU_READING_CSS}
`

/**
 * ViperLogistics UI kit.
 *
 * Every screen imports from '@/components/ui' (relative). Keeping one entry
 * point means a component can move between modules without touching call
 * sites, and it's obvious when something outside the kit is being used.
 */

export {
  cx,
  Button,
  IconButton,
  Tooltip,
  Badge,
  StatusPill,
  Avatar,
  AvatarGroup,
  ProgressBar,
  Kbd,
  Divider,
} from './primitives'
export type { BtnVariant, BtnSize, ButtonProps, IconButtonProps, Tone } from './primitives'

export {
  Field,
  useFieldProps,
  Input,
  SearchInput,
  Textarea,
  Select,
  Checkbox,
  Radio,
  Switch,
  MultiSelect,
  Autocomplete,
  TagsInput,
} from './inputs'
export type { ControlSize, InputProps, TextareaProps, SelectProps } from './inputs'

export {
  Modal,
  Drawer,
  Popover,
  MenuItem,
  MenuSeparator,
  MenuLabel,
  useContextMenu,
  ToastProvider,
  useToast,
  useConfirm,
  usePrompt,
} from './overlay'
export type { ModalSize, ToastKind, ToastOptions, ConfirmOptions, ContextMenuItem } from './overlay'

export { Spinner, Skeleton, SkeletonText, SkeletonCard, SkeletonTable, SkeletonList, EmptyState, ErrorState } from './feedback'
export type { EmptyArt } from './feedback'

export { Card, CardHeader, CardBody, CardFooter, CollapsibleCard, StatCard, PageHeader, FilterBar } from './Card'

export { Tabs, SegmentedControl } from './Tabs'
export type { TabItem } from './Tabs'

export { DataTable, BulkBar } from './DataTable'
export type { Column } from './DataTable'

export { ICON, STROKE } from './icons'

export {
  fmtRelative,
  daysFromToday,
  relativeDayLabel,
  compactNumber,
  pctDelta,
  fmtMoney,
  fmtHoursShort,
} from './format'

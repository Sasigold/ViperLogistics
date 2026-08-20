/**
 * The product's single icon vocabulary.
 *
 * Everything is lucide-react at one of five sizes and one stroke weight, so
 * icons never drift between screens. Import icons from here rather than from
 * 'lucide-react' directly — a second icon set can't creep in through a file
 * that doesn't exist.
 */

export const ICON = {
  /** inside dense grid cells and badges */
  xs: 12,
  /** inline with body text, buttons */
  sm: 14,
  /** default control size */
  md: 16,
  /** navigation, section headers */
  lg: 18,
  /** page headers, stat tiles */
  xl: 20,
  /** empty states, hero marks */
  hero: 24,
} as const

/** lucide's default is 2 — 1.75 sits better next to Heebo's stroke. */
export const STROKE = 1.75

export {
  // navigation
  LayoutDashboard,
  Calendar,
  CalendarDays,
  CalendarClock,
  ClipboardList,
  PartyPopper,
  Users,
  Building2,
  HardHat,
  Settings,
  Truck,
  Menu,
  PanelLeftClose,
  PanelLeftOpen,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  ChevronsUpDown,
  ArrowUp,
  ArrowDown,
  ArrowLeft,
  ArrowRight,
  ExternalLink,
  // actions
  Plus,
  Pencil,
  Trash2,
  Copy,
  Save,
  Check,
  CheckCheck,
  X,
  Search,
  Filter,
  SlidersHorizontal,
  Columns3,
  RotateCcw,
  RefreshCw,
  Download,
  Upload,
  FileSpreadsheet,
  Undo2,
  MoreHorizontal,
  MoreVertical,
  GripVertical,
  Eye,
  EyeOff,
  // status & feedback
  AlertTriangle,
  AlertCircle,
  Info,
  CircleCheck,
  XCircle,
  Loader2,
  Clock,
  History,
  MessageSquarePlus,
  Bell,
  BellOff,
  Smartphone,
  TrendingUp,
  TrendingDown,
  // domain
  MapPin,
  Phone,
  Mail,
  User,
  UserPlus,
  UserCheck,
  Briefcase,
  Package,
  Boxes,
  Wallet,
  Banknote,
  Armchair,
  Receipt,
  HandCoins,
  // fleet (0089)
  Fuel,
  Gauge,
  IdCard,
  ShieldCheck,
  Calculator,
  Percent,
  Lock,
  LockOpen,
  Map,
  Circle,
  Pentagon,
  Timer,
  Sun,
  Moon,
  LogOut,
  LogIn,
  Shield,
  KeyRound,
  Zap,
  LayoutGrid,
  List,
  CalendarCheck,
  CalendarX,
  PlusCircle,
  FileText,
  PencilLine,
  WifiOff,
  BarChart3,
  PieChart,
  Printer,
  Bookmark,
  Paperclip,
  Columns2,
  Image,
  Link2,
} from 'lucide-react'


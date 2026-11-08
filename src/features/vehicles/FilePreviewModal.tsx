import { Download, ExternalLink, ICON, STROKE } from '../../components/ui/icons'
import { Button, EmptyState, Modal, Skeleton } from '../../components/ui'
import { previewKind } from './vehicles'

/**
 * צפייה בקובץ סרוק בלי להוריד אותו: תמונה מוצגת כתמונה, PDF בתוך iframe
 * (מציג ה-PDF של הדפדפן). HEIC אינו מוצג ברוב הדפדפנים, ולכן הוא — וכל סוג
 * אחר — נפתח בלשונית חדשה או יורד.
 *
 * הכתובת היא כתובת חתומה בלי `download`, ולכן הדפדפן מציג ולא שומר.
 */
export function FilePreviewModal({
  open,
  onClose,
  title,
  url,
  loading,
  mimeType,
  fileName,
  onDownload,
}: {
  open: boolean
  onClose: () => void
  title: string
  url: string | null | undefined
  loading?: boolean
  mimeType: string | null | undefined
  fileName: string | null | undefined
  onDownload?: () => void
}) {
  const kind = previewKind(mimeType, fileName)

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="xl"
      title={title}
      description={fileName ?? undefined}
      footer={
        <>
          {url && (
            <Button onClick={() => window.open(url, '_blank', 'noopener')}>
              <ExternalLink size={ICON.sm} strokeWidth={STROKE} />
              פתיחה בלשונית חדשה
            </Button>
          )}
          {onDownload && (
            <Button onClick={onDownload}>
              <Download size={ICON.sm} strokeWidth={STROKE} />
              הורדה
            </Button>
          )}
          <Button variant="primary" onClick={onClose}>
            סגירה
          </Button>
        </>
      }
    >
      {loading || !url ? (
        <Skeleton className="h-[60dvh] w-full" />
      ) : kind === 'image' ? (
        <img src={url} alt={fileName ?? title} className="mx-auto max-h-[65dvh] w-auto max-w-full rounded-lg object-contain" />
      ) : kind === 'pdf' ? (
        <iframe src={url} title={fileName ?? title} className="h-[65dvh] w-full rounded-lg border border-line-subtle bg-white" />
      ) : (
        <EmptyState
          compact
          art="table"
          title="אי אפשר להציג את הקובץ כאן"
          description="הדפדפן אינו מציג קבצים מהסוג הזה (למשל HEIC מאייפון) — אפשר לפתוח אותו בלשונית חדשה או להוריד"
        />
      )}
    </Modal>
  )
}

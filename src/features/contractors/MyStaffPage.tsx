import { Card, EmptyState, PageHeader } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { RequirePermission } from '../auth/guards'
import { WorkersTab } from './ContractorDetailPage'

/**
 * הסגל של הקבלן, כדף.
 *
 * זו הלשונית "העובדים שלי" שהייתה בפורטל, על אותו `WorkersTab` שמשרת גם את
 * מסך הקבלנים במשרד — ההבדל היחיד הוא המפתח שנשלח: `portal.manage_workers`
 * למי שמנהל את הסגל של עצמו, `contractors.manage_workers` למי שמנהל את הסגל
 * של אחרים.
 */
export default function MyStaffPage() {
  return (
    <RequirePermission perm={PERM.PORTAL_MANAGE_WORKERS}>
      <MyStaff />
    </RequirePermission>
  )
}

function MyStaff() {
  const { me, has } = useAuth()
  const contractorId = me?.profile.contractor_id ?? null

  return (
    <div className="space-y-4">
      <PageHeader title="העובדים שלי" subtitle="מי בסגל, ומי מהם כבר מחתים שעון" />
      {contractorId ? (
        <WorkersTab contractorId={contractorId} canManage={has(PERM.PORTAL_MANAGE_WORKERS)} />
      ) : (
        /* אדמין שמציץ במסך: יש לו את המפתח אבל אין לו קבלן, ובלי `contractorId`
           אין סגל לשאול עליו. הסגל של קבלן מסוים יושב ב-/contractors/:id. */
        <Card>
          <EmptyState
            art="alert"
            title="המסך הזה שייך לקבלן"
            description="החשבון שלך אינו משויך לקבלן. את סגל העובדים של קבלן מסוים אפשר לנהל דרך מסך הקבלנים."
          />
        </Card>
      )}
    </div>
  )
}
